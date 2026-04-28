[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$InFile,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$OutFile,

    [Parameter(Position=2, Mandatory=$true)]
    [string]$TargetOs
)

$firstLine = Get-Content -Path $InFile -TotalCount 1 -ErrorAction SilentlyContinue
$content = Get-Content -Path $InFile | Select-Object -Skip 1

if ($TargetOs -eq "windows") {
    if ($firstLine -match "^#!pythonw") {
        $pythonExe = "pythonw.exe"
    } else {
        $pythonExe = "python.exe"
    }
    # A Batch-Python polyglot. Batch executes the first line and exits,
    # while Python (via -x) ignores the first line and executes the rest.
    $wrapper = "@setlocal enabledelayedexpansion & `"%~dp0$pythonExe`" -x `"%~f0`" %* & exit /b !ERRORLEVEL!"
    Set-Content -Path $OutFile -Value $wrapper -Encoding UTF8
} else {
    # A Shell-Python polyglot. The shell executes the triple-quoted 'exec'
    # command, re-running the script with python3 from the scripts directory.
    # Python ignores the triple-quoted string and continues.
    $wrapper = @'
#!/bin/sh
'''exec' "$(dirname "$0")/python3" "$0" "$@"
' '''
'@
    Set-Content -Path $OutFile -Value $wrapper -Encoding UTF8
}

Add-Content -Path $OutFile -Value $content -Encoding UTF8
