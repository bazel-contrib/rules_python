---
trigger: glob
description: Shell / Bash scripting style and portability rules
globs: "*.sh"
---

# Shell Scripting Rules

* Use `elif` instead of nesting `if` inside an `else` block.
* When reading file paths from a manifest or list file, iterate line-by-line
  with `while IFS= read -r file; do ...; done < "$manifest"`. Do not use
  unquoted command substitution (`$(cat "$manifest")`) or suppress ShellCheck
  `SC2046` assuming paths lack spaces.
* Do not create companion `.sh` forwarders that merely pass `"$@"` to another
  executable or script.
* Prefer long option names (e.g., `--force`) over short flags in script and
  subprocess calls. When a short flag has no long form (e.g., `git clean -d -x`)
  or is used for cross-platform compatibility (e.g., BSD/macOS vs. GNU), add an
  inline comment stating the corresponding long flag name and what it does.
* Invoke executable scripts with shebangs directly (`./foo.sh`), not via an
  explicit interpreter (`bash ./foo.sh` or `python3 ./foo.py`).
* For option parsing in Bash scripts, use GNU `getopt` with `--name` and
  long-only option names without custom pre-parsing normalization loops.
* Display exact command lines for key steps using an isolated sub-shell
  (`(set -x; cmd ...)`), keeping high-level `echo` messages outside.
* Include a `Modifies:` section in function doc comments when a function
  mutates global variables, state, or arrays.
* Comment non-obvious Bash parameter expansions (e.g., `${key^^}`).
* Do not append `|| true` to network, Git, or build commands unless failure is
  an expected state documented with an inline comment.
* Under `set -e`, do not check `$?` after a simple command; test failing
  commands directly via `if ! cmd; then` or `cmd || ...`.
