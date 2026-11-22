"""Persistent state, validated configuration, and path resolution for PR Queue."""

from __future__ import annotations

import contextlib
import dataclasses
import json
import logging
import os
import threading
import uuid
from collections.abc import Mapping
from pathlib import Path

from fetch_pr_queue import (
    DEFAULT_MAX_AGE_DAYS,
    DEFAULT_REPO,
    sanitize_log_text,
    validate_repo_slug,
    validate_search_query,
)

# =============================================================================
# 1. Global Constants
# =============================================================================

# Relative to the user's home directory (`home_dir`).
DEFAULT_APP_SUBDIR = Path(".gemini") / "antigravity"
# Relative to the user's home directory (`home_dir`).
DEFAULT_BUILDBUDDY_RC = Path(".config") / "rules_python" / "buildbuddy.bazelrc"
# Relative to the user's home directory (`home_dir`).
DEFAULT_PROJECTS_JSON = Path(".gemini") / "projects.json"

# Allowlist of settings modifiable via HTTP `POST /api/config`; excludes
# `base_repo` so HTTP requests cannot redirect `git -C` to arbitrary paths.
HTTP_MUTABLE_CONFIG_FIELDS = frozenset(
    {
        # keep-sorted start
        "custom_query",
        "exclude_approved_by_me",
        "exclude_authored_by_me",
        "exclude_drafts",
        "max_age_days",
        "repo",
        "review_requested_only",
        "user",
        # keep-sorted end
    }
)

_LOGGER = logging.getLogger("pr_queue.state")


# =============================================================================
# 2. Functions
# =============================================================================


def resolve_app_data_dir(home_dir: Path) -> Path:
    """Returns the IDE app data directory, honoring ANTIGRAVITY_APP_DATA_DIR."""
    override = os.environ.get("ANTIGRAVITY_APP_DATA_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    return (home_dir / DEFAULT_APP_SUBDIR).resolve()


def resolve_data_dir(home_dir: Path) -> Path:
    """Returns persistence dir, honoring PR_QUEUE_DATA_DIR and supervisor env."""
    for env_var in ("PR_QUEUE_DATA_DIR", "ANTIGRAVITY_EXECUTABLE_DATA_DIR"):
        override = os.environ.get(env_var, "").strip()
        if override:
            return Path(override).expanduser().resolve()
    return (resolve_app_data_dir(home_dir) / "pr_queue").resolve()


def parse_bool_field(raw: Mapping[str, object], key: str, default: bool) -> bool:
    """Extracts an optional boolean field, rejecting non-boolean JSON values."""
    if key not in raw or raw[key] is None:
        return default
    val = raw[key]
    if not isinstance(val, bool):
        raise PrQueueError(f"`{key}` must be a boolean.")
    return val


def parse_str_field(raw: Mapping[str, object], key: str, default: str) -> str:
    """Extracts an optional string field, rejecting non-string JSON values."""
    if key not in raw or raw[key] is None:
        return default
    val = raw[key]
    if not isinstance(val, str):
        raise PrQueueError(f"`{key}` must be a string.")
    return val.strip()


def parse_positive_int_field(raw: Mapping[str, object], key: str) -> int:
    """Extracts a required positive integer field, rejecting bools and strings."""
    val = raw.get(key)
    if isinstance(val, bool) or not isinstance(val, int) or val <= 0:
        raise PrQueueError(f"`{key}` must be a positive integer.")
    return val


def _parse_non_negative_int_field(
    raw: Mapping[str, object], key: str, default: int
) -> int:
    val = raw.get(key, default)
    if isinstance(val, bool) or not isinstance(val, int) or val < 0:
        raise PrQueueError(f"`{key}` must be a non-negative integer.")
    return val


def _parse_float_field(raw: Mapping[str, object], key: str, default: float) -> float:
    val = raw.get(key, default)
    if val is None:
        return default
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        raise PrQueueError(f"`{key}` must be a number.")
    return float(val)


# =============================================================================
# 3. Classes
# =============================================================================


class PrQueueError(Exception):
    """Raised on configuration, Git, GitHub, or Language Server RPC errors."""


@dataclasses.dataclass
class PrQueueConfig:
    """User-configurable filter and repository settings for PR Queue."""

    # LINT.IfChange(pr_queue_config_fields)
    # GitHub repository in owner/name format.
    repo: str = DEFAULT_REPO
    # GitHub login for viewer filters; empty resolves via `gh api user`.
    user: str = ""
    # Move PRs untouched for more than this many days to the Stale drawer; 0 = off.
    max_age_days: int = DEFAULT_MAX_AGE_DAYS
    # Include only PRs explicitly requesting a review from `user`.
    review_requested_only: bool = False
    # Hide PRs where `user`'s latest review is APPROVED.
    exclude_approved_by_me: bool = True
    # Hide PRs authored by `user`.
    exclude_authored_by_me: bool = True
    # Hide draft PRs.
    exclude_drafts: bool = True
    # Extra GitHub search filter passed to `gh pr list --search`.
    custom_query: str = ""
    # Optional disk-only override path to local git checkout; empty auto-detects.
    base_repo: str = ""
    # LINT.ThenChange(//.agents/plugins/pr-queue/sidecars/pr_queue/index.html:pr_queue_config_fields)

    @classmethod
    def from_dict(cls, raw: Mapping[str, object]) -> PrQueueConfig:
        """Creates a validated PrQueueConfig from a JSON mapping.

        Args:
          raw: Parsed JSON configuration object.

        Returns:
          Validated PrQueueConfig instance.
        """
        defaults = cls()
        repo = validate_repo_slug(
            parse_str_field(raw, "repo", defaults.repo), error_cls=PrQueueError
        )
        max_age_days = _parse_non_negative_int_field(
            raw, "max_age_days", defaults.max_age_days
        )
        custom_query = validate_search_query(
            parse_str_field(raw, "custom_query", defaults.custom_query),
            error_cls=PrQueueError,
        )

        return cls(
            repo=repo,
            user=parse_str_field(raw, "user", defaults.user),
            max_age_days=max_age_days,
            review_requested_only=parse_bool_field(
                raw, "review_requested_only", defaults.review_requested_only
            ),
            exclude_approved_by_me=parse_bool_field(
                raw, "exclude_approved_by_me", defaults.exclude_approved_by_me
            ),
            exclude_authored_by_me=parse_bool_field(
                raw, "exclude_authored_by_me", defaults.exclude_authored_by_me
            ),
            exclude_drafts=parse_bool_field(
                raw, "exclude_drafts", defaults.exclude_drafts
            ),
            custom_query=custom_query,
            base_repo=parse_str_field(raw, "base_repo", defaults.base_repo),
        )

    def to_dict(self) -> dict[str, object]:
        """Serializes settings into a JSON-compatible dictionary."""
        return dataclasses.asdict(self)


@dataclasses.dataclass
class TriggeredPrRecord:
    """Metadata stored when the user launches a `/review-code` chat for a PR."""

    # GitHub pull request number.
    pr_number: int
    # GitHub repository in owner/name format.
    repo: str
    # Conversation (cascade) UUID.
    conversation_id: str
    # PR title at launch time.
    title: str
    # PR web URL.
    url: str
    # PR head commit SHA checked out when review launched.
    head_sha: str
    # PR source branch name.
    head_ref: str
    # PR author GitHub login.
    author: str
    # Filesystem path to the dedicated review worktree.
    worktree_path: str
    # Language Server project ID associated with the conversation, if any.
    project_id: str
    # Language Server environment ID created or reused for the worktree, if any.
    environment_id: str
    # Unix epoch timestamp when the review conversation was created.
    triggered_at: float

    @classmethod
    def from_dict(cls, raw: Mapping[str, object]) -> TriggeredPrRecord:
        """Reconstructs a TriggeredPrRecord from serialized JSON.

        Args:
          raw: Serialized JSON object for a previously launched PR review.

        Returns:
          Validated TriggeredPrRecord instance.
        """
        conversation_id = parse_str_field(raw, "conversation_id", "")
        if not conversation_id:
            raise ValueError("`conversation_id` must be a non-empty string.")
        return cls(
            pr_number=parse_positive_int_field(raw, "pr_number"),
            repo=parse_str_field(raw, "repo", DEFAULT_REPO) or DEFAULT_REPO,
            conversation_id=conversation_id,
            title=parse_str_field(raw, "title", ""),
            url=parse_str_field(raw, "url", ""),
            head_sha=parse_str_field(raw, "head_sha", ""),
            head_ref=parse_str_field(raw, "head_ref", ""),
            author=parse_str_field(raw, "author", ""),
            worktree_path=parse_str_field(raw, "worktree_path", ""),
            project_id=parse_str_field(raw, "project_id", ""),
            environment_id=parse_str_field(raw, "environment_id", ""),
            triggered_at=_parse_float_field(raw, "triggered_at", 0.0),
        )

    def to_dict(self) -> dict[str, object]:
        """Serializes record into a JSON-compatible dictionary."""
        return dataclasses.asdict(self)


class StateStore:
    """Thread-safe persistent storage for config, triggered chats, and cache."""

    def __init__(self, data_dir: Path) -> None:
        self._data_dir = data_dir
        self._data_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._config_path = self._data_dir / "config.json"
        self._triggered_path = self._data_dir / "triggered_prs.json"
        self._cache_path = self._data_dir / "queue_cache.json"

    @property
    def data_dir(self) -> Path:
        """Returns the backing directory path for state files."""
        return self._data_dir

    @staticmethod
    def record_key(repo: str, pr_number: int) -> str:
        """Returns canonical key combining repo and PR number."""
        return f"{repo.lower()}#{pr_number}"

    def _read_json(self, path: Path, default: object) -> object:
        if not path.is_file():
            return default
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            _LOGGER.warning(
                "Ignoring unreadable state file %s: %s",
                path,
                sanitize_log_text(exc),
            )
            return default

    def _write_json(self, path: Path, payload: object) -> None:
        tmp_path = path.with_name(f".{path.name}.{uuid.uuid4().hex[:8]}.tmp")
        try:
            tmp_path.write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            os.replace(tmp_path, path)
        finally:
            with contextlib.suppress(OSError):
                tmp_path.unlink(missing_ok=True)

    def get_config(self) -> PrQueueConfig:
        """Loads persisted config or returns defaults on missing/invalid data."""
        with self._lock:
            raw = self._read_json(self._config_path, {})
            if not isinstance(raw, dict) or not raw:
                return PrQueueConfig()
            try:
                return PrQueueConfig.from_dict(raw)
            except PrQueueError as exc:
                _LOGGER.warning(
                    "Invalid stored config %s (%s); using defaults.",
                    self._config_path,
                    sanitize_log_text(exc),
                )
                return PrQueueConfig()

    def save_config(self, config: PrQueueConfig) -> PrQueueConfig:
        """Persists updated configuration atomically."""
        with self._lock:
            self._write_json(self._config_path, config.to_dict())
            return config

    def get_triggered_prs(self) -> dict[str, TriggeredPrRecord]:
        """Returns map of `repo#number` keys to TriggeredPrRecord entries."""
        with self._lock:
            raw = self._read_json(self._triggered_path, {})
            if not isinstance(raw, dict):
                return {}
            records: dict[str, TriggeredPrRecord] = {}
            for key, item in raw.items():
                if not isinstance(item, dict) or "conversation_id" not in item:
                    continue
                try:
                    records[str(key)] = TriggeredPrRecord.from_dict(item)
                except (KeyError, PrQueueError, TypeError, ValueError) as exc:
                    _LOGGER.warning(
                        "Ignoring corrupt triggered PR record %r in %s: %s",
                        sanitize_log_text(key),
                        self._triggered_path,
                        sanitize_log_text(exc),
                    )
            return records

    def get_triggered_for_pr(
        self, repo: str, pr_number: int
    ) -> TriggeredPrRecord | None:
        """Looks up triggered review chat record for a PR in repo."""
        records = self.get_triggered_prs()
        return records.get(self.record_key(repo, pr_number))

    def record_triggered_pr(self, record: TriggeredPrRecord) -> None:
        """Saves or updates the triggered chat record for a PR."""
        with self._lock:
            raw = self._read_json(self._triggered_path, {})
            if not isinstance(raw, dict):
                raw = {}
            raw[self.record_key(record.repo, record.pr_number)] = record.to_dict()
            self._write_json(self._triggered_path, raw)

    def get_disk_cache(self) -> dict[str, object] | None:
        """Loads the last persisted PR queue snapshot, if any."""
        with self._lock:
            raw = self._read_json(self._cache_path, None)
            if not isinstance(raw, dict):
                return None
            return {str(k): v for k, v in raw.items()}

    def save_disk_cache(self, payload: Mapping[str, object]) -> None:
        """Persists a fetched PR queue snapshot to disk for offline fallback."""
        with self._lock:
            self._write_json(self._cache_path, dict(payload))
