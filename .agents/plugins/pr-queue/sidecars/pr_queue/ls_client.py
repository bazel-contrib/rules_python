"""Language Server RPC client and IDE workspace/conversation helpers."""

from __future__ import annotations

import asyncio
import contextlib
import dataclasses
import json
import logging
import os
import uuid
from collections.abc import Mapping, Sequence
from http.client import HTTPMessage, HTTPResponse
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse, urlsplit
from urllib.request import (
    HTTPRedirectHandler,
    Request,
    build_opener,
)

from fetch_pr_queue import retry_async, sanitize_log_text
from state_store import PrQueueError

# =============================================================================
# 1. Global Constants
# =============================================================================

DEFAULT_HOST = "127.0.0.1"
# Localhost Language Server RPCs normally complete within milliseconds.
_LS_RPC_TIMEOUT_SECONDS = 5

LOOPBACK_HOSTS = frozenset(
    {
        # keep-sorted start
        "127.0.0.1",
        "::1",
        "localhost",
        # keep-sorted end
    }
)
WILDCARD_HOSTS = frozenset(
    {
        # keep-sorted start
        "0.0.0.0",
        "::",
        # keep-sorted end
    }
)

_TRANSIENT_LS_HTTP_CODES = frozenset(
    {
        # keep-sorted start
        500,
        502,
        503,
        504,
        # keep-sorted end
    }
)

_LOGGER = logging.getLogger("pr_queue.ls")


# =============================================================================
# 2. Functions
# =============================================================================


def uri_to_path(uri: str) -> Path | None:
    """Converts a `file://` URI or absolute path string to a resolved Path."""
    if not uri:
        return None
    if uri.startswith("file://"):
        parsed = urlparse(uri)
        return Path(unquote(parsed.path)).resolve()
    candidate = Path(uri).expanduser()
    if candidate.is_absolute():
        return candidate.resolve()
    return None


def parse_ls_address(raw_addr: str) -> tuple[str, str, int] | None:
    """Parses ANTIGRAVITY_LS_ADDRESS (`host:port` or `http://host:port`)."""
    addr = raw_addr.strip()
    if not addr:
        return None
    target = addr if "://" in addr else f"http://{addr}"
    try:
        parsed = urlsplit(target)
        port = parsed.port
    except ValueError:
        return None
    scheme = parsed.scheme.lower()
    host = (parsed.hostname or DEFAULT_HOST).strip("[]").lower()
    if (
        scheme != "http"
        or port is None
        or not (1 <= port <= 65535)
        or host not in LOOPBACK_HOSTS
    ):
        return None
    return (scheme, host, port)


def _valid_tcp_port(raw_port: object) -> int | None:
    if (
        isinstance(raw_port, int)
        and not isinstance(raw_port, bool)
        and 1 <= raw_port <= 65535
    ):
        return raw_port
    return None


def _ls_credentials_from_env() -> LsCredentials | None:
    ls_addr = os.environ.get("ANTIGRAVITY_LS_ADDRESS", "").strip()
    ls_csrf = os.environ.get("ANTIGRAVITY_CSRF_TOKEN", "").strip()
    parsed_addr = parse_ls_address(ls_addr)
    if parsed_addr and ls_csrf:
        scheme, host, port = parsed_addr
        return LsCredentials(scheme=scheme, host=host, port=port, csrf_token=ls_csrf)
    return None


def _ls_credentials_from_daemon_file(entry: Path) -> LsCredentials | None:
    try:
        payload = json.loads(entry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    csrf = str(payload.get("csrfToken") or "").strip()
    if not csrf:
        return None
    pid = payload.get("pid")
    if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
        try:
            os.kill(pid, 0)
        except OSError:
            return None
    port = _valid_tcp_port(payload.get("httpPort"))
    if port is not None:
        return LsCredentials(
            scheme="http", host=DEFAULT_HOST, port=port, csrf_token=csrf
        )
    return None


def resolve_ls_credentials(daemon_dir: Path) -> LsCredentials:
    """Discovers a local Language Server endpoint and CSRF token.

    Args:
      daemon_dir: Directory containing Language Server daemon registration JSONs.

    Returns:
      Validated LsCredentials for the running Language Server.
    """
    from_env = _ls_credentials_from_env()
    if from_env is not None:
        return from_env

    # Standalone launches outside the supervisor lack LS env vars, so fall back
    # to the Language Server daemon registration files on disk.
    candidates: list[tuple[float, Path]] = []
    if daemon_dir.is_dir():
        for entry in daemon_dir.glob("*.json"):
            with contextlib.suppress(OSError):
                candidates.append((entry.stat().st_mtime, entry))

    candidates.sort(key=lambda item: item[0], reverse=True)
    for _mtime, entry in candidates:
        creds = _ls_credentials_from_daemon_file(entry)
        if creds is not None:
            return creds

    raise PrQueueError(f"Could not locate a running Language Server in {daemon_dir}.")


def _open_ls_request(req: Request, *, timeout: int) -> HTTPResponse:
    opener = build_opener(_NoRedirectHandler())
    return opener.open(req, timeout=timeout)


def call_ls_rpc_sync(
    ls_info: LsCredentials,
    method: str,
    body: Mapping[str, object],
) -> dict[str, object]:
    """Performs a synchronous Connect JSON RPC against the Language Server.

    Args:
      ls_info: Loopback Language Server endpoint and CSRF credentials.
      method: `LanguageServerService` RPC method name.
      body: JSON-serializable RPC request mapping.

    Returns:
      Decoded JSON response dictionary (or `{}` for empty bodies).
    """
    scheme = ls_info.scheme.lower()
    host = ls_info.host.strip("[]").lower()
    if scheme != "http":
        raise PrQueueError(
            f"Unsupported Language Server RPC scheme `{scheme}`; only loopback `http` is supported."
        )
    if host not in LOOPBACK_HOSTS:
        raise PrQueueError(
            f"Refusing Language Server RPC to non-loopback LS host: {host}"
        )
    if isinstance(ls_info.port, bool) or not (1 <= ls_info.port <= 65535):
        raise PrQueueError(f"Invalid Language Server RPC port: {ls_info.port}")

    url_host = f"[{host}]" if ":" in host else host
    url = (
        f"http://{url_host}:{ls_info.port}"
        f"/exa.language_server_pb.LanguageServerService/{method}"
    )
    req = Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-codeium-csrf-token": ls_info.csrf_token,
        },
    )
    raw = _execute_ls_http_call(req, method=method)
    if not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise PrQueueError(
            f"Language Server RPC {method} returned invalid JSON: {exc}"
        ) from exc
    if not isinstance(parsed, dict):
        return {}
    return {str(k): v for k, v in parsed.items()}


def _execute_ls_http_call(req: Request, *, method: str) -> str:
    try:
        with _open_ls_request(req, timeout=_LS_RPC_TIMEOUT_SECONDS) as resp:
            return resp.read().decode("utf-8")
    except HTTPError as exc:
        detail = ""
        with contextlib.suppress(OSError, UnicodeDecodeError):
            detail = exc.read().decode("utf-8", errors="replace")
        msg = (
            f"Language Server RPC {method} failed (HTTP {exc.code}): "
            f"{detail or exc.reason}"
        )
        if exc.code in _TRANSIENT_LS_HTTP_CODES:
            raise _TransientLsRpcError(msg) from exc
        raise PrQueueError(msg) from exc
    except (URLError, OSError, TimeoutError) as exc:
        raise _TransientLsRpcError(
            f"Language Server RPC {method} request error: {exc}"
        ) from exc


async def call_ls_rpc(
    ls_info: LsCredentials,
    method: str,
    body: Mapping[str, object],
    *,
    retryable: bool = False,
) -> dict[str, object]:
    """Invokes a Connect JSON RPC on LanguageServerService.

    Args:
      ls_info: Loopback Language Server endpoint and CSRF credentials.
      method: `LanguageServerService` RPC method name.
      body: JSON-serializable RPC request mapping.
      retryable: If True, retries transient transport/5xx errors with backoff.

    Returns:
      Decoded JSON response dictionary.
    """
    if not retryable:
        return await asyncio.to_thread(call_ls_rpc_sync, ls_info, method, body)
    return await retry_async(
        lambda: asyncio.to_thread(call_ls_rpc_sync, ls_info, method, body),
        is_retryable=lambda exc: isinstance(exc, _TransientLsRpcError),
        label=f"LS RPC {method}",
    )


def _extract_resource_uris_from_list(resources: object) -> list[str]:
    uris: list[str] = []
    if not isinstance(resources, list):
        return uris
    for res in resources:
        if not isinstance(res, dict):
            continue
        direct = res.get("folderUri")
        if isinstance(direct, str) and direct:
            uris.append(direct)
        git_folder = res.get("gitFolder")
        if isinstance(git_folder, dict):
            gf_uri = git_folder.get("folderUri")
            if isinstance(gf_uri, str) and gf_uri:
                uris.append(gf_uri)
    return uris


def _extract_project_resource_uris(project: Mapping[str, object]) -> list[str]:
    proj_res = project.get("projectResources")
    if isinstance(proj_res, dict) and "resources" in proj_res:
        return _extract_resource_uris_from_list(proj_res.get("resources"))
    return _extract_resource_uris_from_list(project.get("resources"))


def _project_environments(project: Mapping[str, object]) -> list[dict[str, object]]:
    envs_container = project.get("environments")
    if isinstance(envs_container, dict):
        raw_envs = envs_container.get("environments", [])
    elif isinstance(envs_container, list):
        raw_envs = envs_container
    else:
        return []
    if not isinstance(raw_envs, list):
        return []
    return [env for env in raw_envs if isinstance(env, dict)]


def _env_paths(env: Mapping[str, object]) -> list[Path]:
    raw_resources = env.get("resources")
    env_resources = (
        raw_resources.get("resources", []) if isinstance(raw_resources, dict) else []
    )
    paths: list[Path] = []
    for uri in _extract_resource_uris_from_list(env_resources):
        parsed = uri_to_path(uri)
        if parsed is not None:
            paths.append(parsed)
    return paths


def _match_project_for_repo(
    projects: Sequence[Mapping[str, object]],
    resolved_main: Path,
    resolved_worktree: Path,
) -> Mapping[str, object] | None:
    for project in projects:
        proj_paths = [
            uri_to_path(uri) for uri in _extract_project_resource_uris(project)
        ]
        if resolved_worktree in proj_paths or resolved_main in proj_paths:
            return project
    for project in projects:
        for env in _project_environments(project):
            paths = _env_paths(env)
            if resolved_worktree in paths or resolved_main in paths:
                return project
    name_matches = [
        project
        for project in projects
        if str(project.get("name") or "") == resolved_main.name
    ]
    if len(name_matches) == 1:
        return name_matches[0]
    return None


async def _list_and_read_projects(ls_info: LsCredentials) -> list[dict[str, object]]:
    list_resp = await call_ls_rpc(ls_info, "ListProjects", {}, retryable=True)
    project_ids = list_resp.get("projectIds")
    if not isinstance(project_ids, list) or not project_ids:
        return []
    read_resp = await call_ls_rpc(
        ls_info, "ReadProjects", {"ids": project_ids}, retryable=True
    )
    projects = read_resp.get("projects", [])
    if not isinstance(projects, list):
        return []
    return [
        project
        for project in projects
        if isinstance(project, dict) and not project.get("archived")
    ]


async def collect_project_paths_from_ls(daemon_dir: Path) -> list[Path]:
    """Queries Language Server projects for registered workspace folder paths."""
    try:
        ls_info = resolve_ls_credentials(daemon_dir)
        projects = await _list_and_read_projects(ls_info)
    except PrQueueError as exc:
        _LOGGER.debug("Skipping LS project discovery: %s", sanitize_log_text(exc))
        return []

    paths: list[Path] = []
    for project in projects:
        for uri in _extract_project_resource_uris(project):
            local = uri_to_path(uri)
            if local and local not in paths:
                paths.append(local)
    return paths


def collect_project_paths_from_disk(projects_file: Path) -> list[Path]:
    """Reads candidate folder paths from `projects.json` when LS is offline."""
    if not projects_file.is_file():
        return []
    try:
        data = json.loads(projects_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _LOGGER.warning("Unable to parse %s: %s", projects_file, sanitize_log_text(exc))
        return []

    paths: list[Path] = []

    def _visit(node: object) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(key, str) and (
                    key.startswith("/") or key.startswith("file://")
                ):
                    parsed = uri_to_path(key)
                    if parsed and parsed not in paths:
                        paths.append(parsed)
                if key in ("folderUri", "path", "root", "folder") and isinstance(
                    value, str
                ):
                    parsed = uri_to_path(value)
                    if parsed and parsed not in paths:
                        paths.append(parsed)
                else:
                    _visit(value)
        elif isinstance(node, list):
            for item in node:
                _visit(item)

    _visit(data)
    return paths


async def _lookup_project_by_conversation(
    ls_info: LsCredentials,
    projects: Sequence[Mapping[str, object]],
    source_conversation_id: str,
) -> Mapping[str, object] | None:
    if not source_conversation_id:
        return None
    try:
        meta_resp = await call_ls_rpc(
            ls_info,
            "GetConversationMetadata",
            {"conversationId": source_conversation_id},
            retryable=True,
        )
    except PrQueueError as exc:
        _LOGGER.warning(
            "GetConversationMetadata failed for %s: %s",
            sanitize_log_text(source_conversation_id),
            sanitize_log_text(exc),
        )
        return None
    metadata = meta_resp.get("metadata") if isinstance(meta_resp, dict) else None
    if not isinstance(metadata, dict):
        return None
    project_id = str(metadata.get("projectId") or "").strip()
    if not project_id or project_id == "outside-of-project":
        return None
    for project in projects:
        if str(project.get("id") or "").strip() == project_id:
            return project
    return None


def _find_matching_env_id(
    project: Mapping[str, object],
    resolved_worktree: Path,
    worktree_name: str,
) -> str:
    env_list = _project_environments(project)
    for env in env_list:
        if resolved_worktree in _env_paths(env):
            env_id = str(env.get("id") or "").strip()
            if env_id:
                return env_id
    for env in env_list:
        if str(env.get("name") or "") == worktree_name:
            env_id = str(env.get("id") or "").strip()
            if env_id:
                return env_id
    return ""


async def ensure_project_environment(
    ls_info: LsCredentials,
    main_repo: Path,
    worktree_path: Path,
    *,
    source_conversation_id: str = "",
) -> tuple[str, str]:
    """Finds or registers a workspace project environment for worktree_path.

    Args:
      ls_info: Loopback Language Server endpoint and CSRF credentials.
      main_repo: Primary local Git repository path.
      worktree_path: Dedicated review worktree directory path.
      source_conversation_id: Optional active chat ID for project fallback.

    Returns:
      Tuple `(project_id, environment_id)` in the Language Server workspace.
    """
    projects = await _list_and_read_projects(ls_info)
    resolved_main = main_repo.resolve()
    resolved_worktree = worktree_path.resolve()

    matched_project = _match_project_for_repo(
        projects, resolved_main, resolved_worktree
    )
    if matched_project is None and source_conversation_id:
        matched_project = await _lookup_project_by_conversation(
            ls_info, projects, source_conversation_id
        )
    if matched_project is None:
        raise PrQueueError(
            f"Could not find a workspace project for `{resolved_main}`. "
            "Open the repository workspace in the agent IDE before launching a review."
        )

    project_id = str(matched_project.get("id") or "").strip()
    if not project_id:
        raise PrQueueError(
            f"Matched workspace project for `{resolved_main}` has no ID."
        )

    existing_env_id = _find_matching_env_id(
        matched_project, resolved_worktree, worktree_path.name
    )
    if existing_env_id:
        return (project_id, existing_env_id)

    new_env_id = str(uuid.uuid4())
    add_req = {
        "projectId": project_id,
        "environment": {
            "id": new_env_id,
            "name": worktree_path.name,
            "resources": {"resources": [{"folderUri": resolved_worktree.as_uri()}]},
        },
    }
    add_resp = await call_ls_rpc(ls_info, "AddEnvironmentToProject", add_req)
    returned_env = add_resp.get("environment")
    if isinstance(returned_env, dict) and returned_env.get("id"):
        return (project_id, str(returned_env["id"]))
    return (project_id, new_env_id)


def _extract_non_disabled_model(entry: object, *, alias_key: str = "") -> str:
    """Returns stripped model ID from an enabled config or model entry."""
    if not isinstance(entry, dict) or entry.get("disabled"):
        return ""
    target = entry.get(alias_key) if alias_key else entry
    if not isinstance(target, dict):
        return ""
    return str(target.get("model") or "").strip()


def _extract_model_from_config_data(data: Mapping[str, object]) -> str:
    model_val = _extract_non_disabled_model(
        data.get("defaultOverrideModelConfig"), alias_key="modelOrAlias"
    )
    if model_val:
        return model_val

    client_configs = data.get("clientModelConfigs")
    if not isinstance(client_configs, list):
        return ""
    for cfg in client_configs:
        model_val = _extract_non_disabled_model(cfg, alias_key="modelOrAlias")
        if model_val:
            return model_val
    return ""


async def _resolve_model_from_available_models(ls_info: LsCredentials) -> str:
    try:
        resp = await call_ls_rpc(ls_info, "GetAvailableModels", {}, retryable=True)
    except PrQueueError as exc:
        _LOGGER.warning("GetAvailableModels failed: %s", sanitize_log_text(exc))
        return ""
    inner = resp.get("response") if isinstance(resp, dict) else None
    if not isinstance(inner, dict):
        return ""
    models = inner.get("models")
    if not isinstance(models, dict):
        return ""

    candidate_ids: list[str] = []
    default_agent_id = str(inner.get("defaultAgentModelId") or "").strip()
    if default_agent_id:
        candidate_ids.append(default_agent_id)
    tiered = inner.get("tieredModelIds")
    if isinstance(tiered, dict):
        for tier in ("pro", "flash", "flashLite"):
            entries = tiered.get(tier)
            if isinstance(entries, list):
                candidate_ids.extend(str(x) for x in entries if x)

    for model_id in candidate_ids:
        model_val = _extract_non_disabled_model(models.get(model_id))
        if model_val:
            return model_val

    for details in models.values():
        model_val = _extract_non_disabled_model(details)
        if model_val:
            return model_val
    return ""


async def resolve_default_model(ls_info: LsCredentials) -> str:
    """Resolves a preferred model enum/ID from Language Server model config RPCs.

    Args:
      ls_info: Loopback Language Server endpoint and CSRF credentials.

    Returns:
      Model identifier or enum string accepted by `StartCascade`.
    """
    try:
        cfg_resp = await call_ls_rpc(
            ls_info, "GetCascadeModelConfigData", {}, retryable=True
        )
    except PrQueueError as exc:
        _LOGGER.warning(
            "GetCascadeModelConfigData failed; trying GetAvailableModels: %s",
            sanitize_log_text(exc),
        )
    else:
        if isinstance(cfg_resp, dict):
            model_val = _extract_model_from_config_data(cfg_resp)
            if model_val:
                return model_val

    fallback = await _resolve_model_from_available_models(ls_info)
    if fallback:
        return fallback
    raise PrQueueError("Could not determine a default model from the Language Server.")


async def start_pr_review_conversation(
    *,
    main_repo: Path,
    worktree_path: Path,
    prompt: str,
    title: str,
    daemon_dir: Path,
    source_conversation_id: str = "",
) -> tuple[str, str, str]:
    """Starts a new agent conversation bound to worktree_path and sends prompt.

    Args:
      main_repo: Primary local Git repository path.
      worktree_path: Dedicated worktree directory checked out for the PR.
      prompt: Initial user message sent to the new conversation.
      title: Conversation title annotation.
      daemon_dir: Language Server daemon directory for local credential discovery.
      source_conversation_id: Optional active conversation ID from the side panel.

    Returns:
      Tuple `(conversation_id, project_id, environment_id)`.
    """
    ls_info = resolve_ls_credentials(daemon_dir)
    project_id, env_id = await ensure_project_environment(
        ls_info,
        main_repo,
        worktree_path,
        source_conversation_id=source_conversation_id,
    )
    requested_model = await resolve_default_model(ls_info)
    planner_config: dict[str, object] = {
        "planModel": requested_model,
        "requestedModel": {"model": requested_model},
    }

    start_req: dict[str, object] = {
        "source": "CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT",
        "trajectoryType": "CORTEX_TRAJECTORY_TYPE_CASCADE",
        "projectEnvConfig": {
            "projectId": project_id,
            "environmentId": env_id,
        },
        "requestedModel": requested_model,
    }
    start_resp = await call_ls_rpc(ls_info, "StartCascade", start_req)
    cascade_id = str(start_resp.get("cascadeId") or "").strip()
    if not cascade_id:
        raise PrQueueError("Language Server `StartCascade` did not return a cascadeId.")

    if title:
        try:
            await call_ls_rpc(
                ls_info,
                "UpdateConversationAnnotations",
                {
                    "cascadeIds": [cascade_id],
                    "annotations": {"title": title},
                    "mergeAnnotations": True,
                },
            )
        except PrQueueError as exc:
            _LOGGER.warning(
                "Failed setting title for conversation %s: %s",
                sanitize_log_text(cascade_id),
                sanitize_log_text(exc),
            )

    await call_ls_rpc(
        ls_info,
        "SendUserCascadeMessage",
        {
            "cascadeId": cascade_id,
            "items": [{"text": prompt}],
            "cascadeConfig": {"plannerConfig": planner_config},
            "blocking": False,
        },
    )
    return (cascade_id, project_id, env_id)


# =============================================================================
# 3. Classes
# =============================================================================


@dataclasses.dataclass(frozen=True)
class LsCredentials:
    """Validated loopback Language Server RPC connection details."""

    # Transport scheme (`http`).
    scheme: str
    # Loopback hostname or IP (`127.0.0.1`, `localhost`, or `::1`).
    host: str
    # Loopback TCP port (`1..65535`).
    port: int
    # CSRF token sent via `x-codeium-csrf-token`.
    csrf_token: str


class _NoRedirectHandler(HTTPRedirectHandler):
    """Rejects HTTP redirects so CSRF credentials are never forwarded off-host."""

    def redirect_request(
        self,
        req: Request,
        fp: object,
        code: int,
        msg: str,
        headers: HTTPMessage,
        newurl: str,
    ) -> Request | None:
        raise PrQueueError(f"HTTP redirect ({code}) rejected for Language Server RPC.")


class _TransientLsRpcError(PrQueueError):
    """Raised on retryable Language Server transport/5xx errors."""
