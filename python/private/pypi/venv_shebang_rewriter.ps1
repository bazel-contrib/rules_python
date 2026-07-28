[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$InFile,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$OutFile,

    [Parameter(Position=2, Mandatory=$true)]
    [string]$TargetOs
)

$ErrorActionPreference = "Stop"

$firstLine = Get-Content -Path $InFile -TotalCount 1 -ErrorAction SilentlyContinue
$content = Get-Content -Path $InFile | Select-Object -Skip 1

$Utf8NoBom = New-Object System.Text.UTF8Encoding $False

if ($TargetOs -eq "windows") {
    if ($firstLine -match "^#!pythonw") {
        $pythonExe = "pythonw.exe"
    } else {
        $pythonExe = "python.exe"
    }
    # A Batch-Python polyglot. Batch executes the first line and exits,
    # while Python (via -x) ignores the first line and executes the rest.
    $wrapper = "@setlocal enabledelayedexpansion & `"%~dp0$pythonExe`" -x `"%~f0`" %* & exit /b !ERRORLEVEL!"
    [System.IO.File]::WriteAllText($OutFile, $wrapper + "`r`n", $Utf8NoBom)
} else {
    # A Shell-Python polyglot. The shell executes the triple-quoted 'exec'
    # command, re-running the script with python3 from the scripts directory.
    # Python ignores the triple-quoted string and continues.
    $wrapper = @"
#!/bin/sh
'''exec' "`$(dirname "`$0")/python3" "`$0" "`$@"
' '''
"@
    [System.IO.File]::WriteAllText($OutFile, $wrapper + "`n", $Utf8NoBom)
}

if ($null -ne $content) {
    [System.IO.File]::AppendAllLines($OutFile, [string[]]$content, $Utf8NoBom)
}
