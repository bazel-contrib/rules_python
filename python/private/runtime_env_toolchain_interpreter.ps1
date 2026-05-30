# PowerShell equivalent of runtime_env_toolchain_interpreter.sh

$ErrorActionPreference = "Stop"

function Die {
    param([string]$message)
    $header = ("Error occurred while attempting to use the deprecated Python "
        + "toolchain `n(@rules_python//python/runtime_env_toolchain:all).")
    Write-Error "$header`n$message"
    exit 1
}

# Try the "python3" command name first, then fall back on "python".
$pythonBin = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $pythonBin) {
    $pythonBin = Get-Command python -ErrorAction SilentlyContinue
}

if (-not $pythonBin) {
    Die ("Neither 'python3' nor 'python' were found on the target platform's "
        + "PATH, which is:`n`n$($env:PATH)`n`nPlease ensure an interpreter "
        + "is available on this platform (and marked executable), or else "
        + "register an appropriate Python toolchain as per the "
        + "documentation for py_runtime_pair "
        + "(https://github.com/bazel-contrib/rules_python/blob/master/"
        + "docs/python.md#py_runtime_pair).")
}

# Because this is a wrapper script that invokes Python, it prevents Python
# from detecting virtualenvs like normal (i.e. using the venv symlink to
# find the real interpreter). To work around this, we have to manually
# detect the venv, then trick the interpreter into understanding we're in a
# virtual env.
$selfDir = $PSScriptRoot
$venvPath = Join-Path $selfDir "pyvenv.cfg"
$venvParentPath = Join-Path $selfDir "..\pyvenv.cfg"

if ((Test-Path $venvPath) -or (Test-Path $venvParentPath)) {
    $venvBin = $MyInvocation.MyCommand.Path
    if (-not (Test-Path $pythonBin.Source)) {
        Die "ERROR: Python interpreter does not exist: $($pythonBin.Source)"
    }
    # PYTHONEXECUTABLE is also used because switching argv0 doesn't fully
    # trick the pyenv wrappers.
    # NOTE: The PYTHONEXECUTABLE envvar only works for non-Mac starting in
    # Python 3.11
    $env:PYTHONEXECUTABLE = $venvBin
}
# NOTE: Windows doesn't have an exec equivalent. The call operator (&)
# creates a sub-process, which is the closest equivalent.
& $pythonBin.Source $args
