# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import pathlib
import shutil
import subprocess
import tempfile

from absl.testing import absltest

from python.runfiles import Runfiles


class GitTest(absltest.TestCase):
    def setUp(self):
        super().setUp()
        r = Runfiles.Create()
        rlocation = os.environ.get("SPHINXDOCS_RLOCATION")
        if not rlocation:
            self.fail("SPHINXDOCS_RLOCATION environment variable not set.")
        sphinx_bzl_path = r.Rlocation(rlocation)
        if not sphinx_bzl_path or not os.path.exists(sphinx_bzl_path):
            self.fail(f"Could not locate runfile for SPHINXDOCS_RLOCATION={rlocation}")
        # Resolve the symlink FIRST to get the real source file path on disk,
        # then take parent.parent to find the real @sphinxdocs workspace root.
        real_sphinx_bzl = pathlib.Path(sphinx_bzl_path).resolve()
        self.sphinxdocs_root = real_sphinx_bzl.parent.parent
        # When running inside Bazel py_test actions (with strict action env enabled),
        # PATH is set to a minimal default like /bin:/usr/bin:/usr/local/bin.
        # This excludes macOS ARM Homebrew (/opt/homebrew/bin) and user-local
        # installations (~/.local/bin), so we append these standard directories to PATH.
        search_path = os.pathsep.join(
            filter(
                None,
                [
                    os.environ.get("PATH"),
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "/usr/bin",
                    "/bin",
                    str(pathlib.Path.home() / ".local" / "bin"),
                ],
            )
        )
        os.environ["PATH"] = search_path
        # Resolve the Bazel binary across various test invocation contexts:
        # - BAZEL: Explicit flag or --test_env passed to py_test
        # - BIT_BAZEL_BINARY: Provided by rules_bazel_integration_test (BIT) runner
        # - shutil.which: Fallback to globally installed bazel/bazelisk (e.g. in CI system PATH)
        self.bazel_bin = (
            os.environ.get("BAZEL")
            or os.environ.get("BIT_BAZEL_BINARY")
            or shutil.which("bazelisk")
            or shutil.which("bazel")
        )
        if not self.bazel_bin:
            self.fail(
                "Could not find bazel or bazelisk executable in PATH or BAZEL env var."
            )

    def _run_cmd(self, cmd: list[str], cwd: pathlib.Path, check: bool = True):
        print(f"\nRunning command: {' '.join(cmd)} in {cwd}")
        res = subprocess.run(
            cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
        )
        if check and res.returncode != 0:
            self.fail(f"Command failed: {' '.join(cmd)}\nOutput:\n{res.stdout}")
        return res

    def _create_test_workspace(self, repo: pathlib.Path):
        downloader_cfg = (self.sphinxdocs_root / "downloader_config.cfg").as_posix()
        # Ignore bazel output symlink trees so `git add .` when committing on branches
        # never tracks or deletes `bazel-bin`, `bazel-out`, etc. across checkouts.
        (repo / ".gitignore").write_text("bazel-*\n")
        # Disable action caching (`build --noremote_accept_cached`) and disk caching
        # (`common --disk_cache=`) so Bazel is forced to dispatch incremental build requests
        # directly to the running persistent worker instead of restoring pre-built HTML
        # results from previous branch steps.
        (repo / ".bazelrc").write_text(
            "common:fast-tests --build_tag_filters=-large,-enormous,-integration-test\n"
            "common:fast-tests --test_tag_filters=-large,-enormous,-integration-test\n"
            "common --disk_cache=\n"
            "build --noremote_accept_cached\n"
            "common --http_timeout_scaling=10.0\n"
            "common --experimental_repository_downloader_retries=10\n"
            f"common --downloader_config={downloader_cfg}\n"
            "common --lockfile_mode=off\n"
        )

        sphinxdocs_root_str = str(self.sphinxdocs_root).replace("\\", "/")
        (repo / "MODULE.bazel").write_text(f"""\
module(name = "test_persistent_worker", version = "0.0.0")

bazel_dep(name = "sphinxdocs", version = "0.0.0")
local_path_override(
    module_name = "sphinxdocs",
    path = "{sphinxdocs_root_str}",
)

bazel_dep(name = "rules_python", version = "1.8.5")

dev_pip = use_extension(
    "@rules_python//python/extensions:pip.bzl",
    "pip",
    dev_dependency = True,
)
dev_pip.parse(
    hub_name = "dev_pip",
    python_version = "3.11",
    requirements_lock = "@rules_python//docs:requirements.txt",
)
use_repo(dev_pip, "dev_pip")
""")

        (repo / "conf.py").write_text('master_doc = "index"\n')

        (repo / "index.rst").write_text(
            "Sphinxdocs Example\n"
            "==================\n\n"
            "Initial doc content.\n\n"
            ".. toctree::\n"
            "   :glob:\n\n"
            "   *\n"
        )

        (repo / "initial_doc.rst").write_text(
            "Initial Doc\n===========\n\nSome initial content.\n"
        )

        (repo / "BUILD.bazel").write_text("""\
load("@sphinxdocs//sphinxdocs:sphinx.bzl", "sphinx_build_binary", "sphinx_docs")

sphinx_docs(
    name = "docs",
    srcs = glob(["*.rst"]),
    config = "conf.py",
    formats = ["html"],
    sphinx = ":sphinx-build",
    allow_persistent_workers = True,
    extra_opts = ["--fail-on-warning"],
)

sphinx_build_binary(
    name = "sphinx-build",
    deps = [
        "@dev_pip//sphinx",
    ],
)
""")

    def test_git_branch_workflow(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = pathlib.Path(tmpdir)
            self._create_test_workspace(repo)

            # 1. Initialize git repo and make initial commit on main
            self._run_cmd(["git", "init"], cwd=repo)
            self._run_cmd(["git", "config", "user.name", "Test User"], cwd=repo)
            self._run_cmd(["git", "config", "user.email", "test@example.com"], cwd=repo)
            self._run_cmd(["git", "add", "."], cwd=repo)
            self._run_cmd(["git", "commit", "-m", "Initial commit"], cwd=repo)
            self._run_cmd(["git", "branch", "-M", "main"], cwd=repo)

            # 2. Build the docs on default branch (main)
            self._run_cmd(
                [self.bazel_bin, "build", "--config=fast-tests", "//:docs"], cwd=repo
            )

            # 3. Create a git branch
            self._run_cmd(["git", "checkout", "-b", "new_branch"], cwd=repo)

            # 4. Create some new docs in that branch without modifying `index.rst`.
            # Because `index.rst` uses `:glob: *`, Sphinx should automatically discover
            # `new_doc.rst` without requiring modifications to `index.rst` on disk.
            (repo / "new_doc.rst").write_text("New Doc\n=======\n\nNew doc content.\n")

            # 5. Commit
            self._run_cmd(["git", "add", "."], cwd=repo)
            self._run_cmd(["git", "commit", "-m", "Add new doc"], cwd=repo)

            # 6. Build docs again in the new branch. Verify incremental worker updates
            # properly mark `index.rst` as outdated so `new_doc.html` is added to its toctree.
            self._run_cmd(
                [self.bazel_bin, "build", "--config=fast-tests", "//:docs"], cwd=repo
            )
            self._check_index_html(repo, "new_doc.html", should_exist=True)

            # 7. Switch back to default branch (main), deleting `new_doc.rst` from disk.
            self._run_cmd(["git", "checkout", "main"], cwd=repo)

            # 8. Build again on main. Ensure persistent worker incremental state invalidates
            # `index.rst` when `new_doc` is removed and deletes stale symlinks in `_sources`
            # so the build succeeds cleanly without referencing `new_doc.html`.
            self._run_cmd(
                [self.bazel_bin, "build", "--config=fast-tests", "//:docs"], cwd=repo
            )
            self._check_index_html(repo, "new_doc.html", should_exist=False)

    def _check_index_html(self, repo: pathlib.Path, text: str, should_exist: bool):
        """Verify whether generated `index.html` contains the expected reference."""
        index_html_files = list(repo.glob("bazel-bin/**/index.html"))
        if not index_html_files:
            self.fail(f"Could not find index.html inside {repo / 'bazel-bin'}")
        content = index_html_files[0].read_text()
        if should_exist:
            self.assertIn(
                text,
                content,
                f"Expected '{text}' in index.html after build, but not found.\nContent:\n{content}",
            )
        else:
            self.assertNotIn(
                text,
                content,
                f"Expected '{text}' NOT to be in index.html after build, but found it.\nContent:\n{content}",
            )


if __name__ == "__main__":
    absltest.main()
