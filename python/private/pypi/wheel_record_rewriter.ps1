[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$InFile,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$OutFile,

    [Parameter(Position=2, Mandatory=$true)]
    [string]$TargetOs,

    [Parameter(Position=3, Mandatory=$true)]
    [string]$DataDirBasename
)

$ErrorActionPreference = "Stop"

$dataPrefix = "$DataDirBasename/"
$quotedDataPrefix = "`"$DataDirBasename/"

if ($TargetOs -eq "windows") {
    $dataRepl = "../../"
    $headersRepl = "../../Include/"
    $platlibRepl = ""
    $purelibRepl = ""
    $scriptsRepl = "../../Scripts/"
} else {
    $dataRepl = "../../../"
    $headersRepl = "../../../include/"
    $platlibRepl = ""
    $purelibRepl = ""
    $scriptsRepl = "../../../bin/"
}

$lines = Get-Content -Path $InFile
$outLines = [System.Collections.Generic.List[string]]::new()
$Utf8NoBom = New-Object System.Text.UTF8Encoding $False

foreach ($line in $lines) {
    if ($line.StartsWith($quotedDataPrefix)) {
        $quote = "`""
        $rest = $line.Substring($quotedDataPrefix.Length)
    } elseif ($line.StartsWith($dataPrefix)) {
        $quote = ""
        $rest = $line.Substring($dataPrefix.Length)
    } else {
        $outLines.Add($line)
        continue
    }

    if ($rest.StartsWith("purelib/")) {
        $outLines.Add($quote + $purelibRepl + $rest.Substring(8))
    } elseif ($rest.StartsWith("platlib/")) {
        $outLines.Add($quote + $platlibRepl + $rest.Substring(8))
    } elseif ($rest.StartsWith("scripts/")) {
        $outLines.Add($quote + $scriptsRepl + $rest.Substring(8))
    } elseif ($rest.StartsWith("headers/")) {
        $outLines.Add($quote + $headersRepl + $rest.Substring(8))
    } elseif ($rest.StartsWith("data/")) {
        $outLines.Add($quote + $dataRepl + $rest.Substring(5))
    } else {
        $outLines.Add($line)
    }
}

[System.IO.File]::WriteAllLines($OutFile, $outLines, $Utf8NoBom)
