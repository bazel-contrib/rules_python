---
trigger: always_on
---

# No Auth Token in Cmdline Rule

* NEVER pass `gh auth token` or embed authentication tokens in command line
  arguments or URLs. Doing so can leak credentials in process tables (`ps`),
  shell history, or logs.
* Use configured SSH keys, standard `git push`, or `gh` commands natively
  instead.
