(pip) Respect dependency-edge platform markers in `uv.lock` when selecting
packages and artifacts, so dependencies reachable only on Linux are not
installed on macOS. Preserve version forks and follow requested dependency
extras when walking the workspace dependency graph.
