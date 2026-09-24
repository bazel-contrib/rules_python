"""Build contracts shared by directory and ZIP application transports."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python:py_executable_info.bzl", "PyExecutableInfo")
load("//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//python/private:py_application_info.bzl", "PyApplicationInfo")  # buildifier: disable=bzl-visibility

def _test_directory_image(name):
    analysis_test(name = name, impl = _test_directory_image_impl, target = ":cleanup_venv")

def _test_directory_image_impl(env, target):
    image = target[PyApplicationInfo]
    public = target[PyExecutableInfo]
    files = image.runfiles.files.to_list()
    env.expect.that_collection(files).contains_at_least(public.app_runfiles.files.to_list())
    env.expect.that_collection(files).contains(image.spec)
    env.expect.that_collection(files).contains(public.stage2_bootstrap)
    env.expect.that_bool(image.settings["entry"].endswith(public.stage2_bootstrap.short_path)).equals(True)
    env.expect.that_collection([file.basename for file in files]).contains_at_least([
        "entry.py",
        "environment.py",
        "process.py",
        "storage.py",
        "model.py",
        "bootstrap_cleanup.py",
    ])
    env.expect.that_collection([a.mnemonic for a in target.actions]).contains_none_of([
        "PyBootstrapTemplate",
    ])

def _test_archive_image(name):
    analysis_test(name = name, impl = _test_archive_image_impl, target = ":cleanup_zipapp")

def _test_archive_image_impl(env, target):
    archives = [a for a in target.actions if a.mnemonic == "PyApplicationArchive"]
    env.expect.that_int(len(archives)).equals(1)
    inputs = [file.basename for file in archives[0].inputs.to_list()]
    env.expect.that_collection(inputs).contains_at_least([
        "cleanup_venv.application.json",
        "cleanup_venv.application_links.jsonl",
        "entry.py",
        "environment.py",
    ])

    # Packaging uses the binary's environment and entry, with no second venv.
    env.expect.that_collection(inputs).contains_none_of([
        "cleanup_zipapp.application.json",
        "cleanup_zipapp.application_links.jsonl",
    ])

def application_test_suite(name):
    test_suite(name = name, tests = [_test_directory_image, _test_archive_image])

def _template_fixture_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(output, ctx.attr.contents)
    return [DefaultInfo(files = depset([output]))]

template_fixture = rule(
    implementation = _template_fixture_impl,
    attrs = {"contents": attr.string()},
)

def _template_output_impl(ctx):
    binary = ctx.attr.binary[DefaultInfo]
    path = binary.files_to_run.executable.path
    if path.endswith(".exe"):
        path = path[:-4]
    outputs = [file for file in binary.files.to_list() if file.path == path]
    if len(outputs) != 1:
        fail("Expected one text bootstrap output for {}".format(ctx.attr.binary.label))
    return [DefaultInfo(files = depset(outputs))]

template_output = rule(
    implementation = _template_output_impl,
    attrs = {"binary": attr.label(mandatory = True)},
)

def _public_executable_impl(ctx):
    binary = ctx.attr.binary
    public = binary[PyExecutableInfo]
    if ctx.file.supplied_venv:
        # A public provider may supply its executable independently of the
        # optional interpreter runfiles collection.
        public = PyExecutableInfo(
            app_runfiles = public.app_runfiles,
            interpreter_args = public.interpreter_args,
            stage2_bootstrap = public.stage2_bootstrap,
            venv_app_symlinks = public.venv_app_symlinks,
            venv_interpreter_runfiles = None,
            venv_interpreter_symlinks = depset(),
            venv_python_exe = ctx.file.supplied_venv,
        )
    return [public, binary[PyRuntimeInfo]]

public_executable = rule(
    implementation = _public_executable_impl,
    attrs = {
        "binary": attr.label(providers = [PyExecutableInfo, PyRuntimeInfo]),
        "supplied_venv": attr.label(allow_single_file = True),
    },
)
