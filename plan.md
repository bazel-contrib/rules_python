# Plan for adding uv.lock support to pip.parse

## Part 1: Analyze and Plan (Done)
- Analyzed `python/extensions/pip.bzl`, `python/private/pypi/hub_builder.bzl`, `python/private/pypi/uv_lock.bzl`.
- Confirmed `uv.lock` structure contains wheel URLs and resolution markers.
- Identified need to modify `pip_repository_attrs.bzl` and `hub_builder.bzl`.

## Part 2: Basic Implementation
1.  **Modify `python/private/pypi/pip_repository_attrs.bzl`**:
    - Add `uv_lock` attribute (label, allow_single_file=True).
    - Add `_toml2json` attribute (label, default pointing to a tool). Note: Need to verify if `_toml2json` is already available or needs to be added. The `uv_lock.bzl` helper uses `attr._toml2json`, so it must be present on the calling rule/tag.

2.  **Modify `python/private/pypi/hub_builder.bzl`**:
    - In `_pip_parse`:
        - Check if `pip_attr.uv_lock` is set.
        - If set, call `convert_uv_lock_to_json`.
        - Parse the JSON result.
        - Iterate over packages in the JSON.
        - Group packages by name.
        - For this step, select the highest version for each package name.
        - Select the first wheel URL for that version.
        - Create `whl_library` repositories for these wheels.
        - Ensure these `whl_library` calls are integrated into `self._whl_libraries`.

3.  **Verify**:
    - Run `bazel run //tests/uv_pypi:bin`.

## Part 3: Advanced Implementation (Multiple Versions)
1.  **Handle Resolution Markers**:
    - Parse `resolution-markers` from `uv.lock` packages.
    - Instead of picking one version, keep all versions that have distinct resolution markers.

2.  **Use `wheel_tags_settings`**:
    - In `hub_builder.bzl`, when constructing the hub repository content (via `hub_repository`), we need to pass information about these multiple versions.
    - The `hub_repository` rule (or the macros creating it) needs to generate `define_wheel_tag_settings` in the `BUILD.bazel` of the hub.
    - Generate `alias` targets using `select()` based on the defined settings.

3.  **Refactor Hub Generation**:
    - Update `hub_repository.bzl` (or the template it uses) to support this new "multi-version via select" pattern, if it doesn't already. The prompt suggests modifying the "hub build file for a package".

4.  **Verify**:
    - Run the test again. It should correctly pick `absl-py` 2.3.1 or 2.4.0 based on the environment/platform.
