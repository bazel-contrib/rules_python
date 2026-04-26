[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$InFile,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$OutFile
)

if ($InFile.EndsWith(".exe") -or $InFile.EndsWith(".dll")) {
    Copy-Item -Path $InFile -Destination $OutFile
    exit 0
}

$firstLine = Get-Content -Path $InFile -TotalCount 1 -ErrorAction SilentlyContinue

if ($firstLine -match "^#!python") {
    $content = Get-Content -Path $InFile | Select-Object -Skip 1
    $wrapper = @'
#!/bin/sh
'''exec' "$(dirname "$0")/python3" "$0" "$@"
' '''
'@
    Set-Content -Path $OutFile -Value $wrapper -Encoding UTF8
    Add-Content -Path $OutFile -Value $content -Encoding UTF8
} else {
    Copy-Item -Path $InFile -Destination $OutFile
}
