$OutputPath = $env:OUTPUT
$Lines = @(
    "TARGET $env:TARGET",
    "CONFIG_MODE $env:CONFIG_MODE",
    "STAMPED $env:STAMPED"
)

$VersionFilePath = $env:VERSION_FILE
if (-not [string]::IsNullOrEmpty($VersionFilePath) -and (Test-Path $VersionFilePath)) {
    $Lines += Get-Content -Path $VersionFilePath
}

$InfoFilePath = $env:INFO_FILE
if (-not [string]::IsNullOrEmpty($InfoFilePath) -and (Test-Path $InfoFilePath)) {
    $Lines += Get-Content -Path $InfoFilePath
}

# Use .NET to write file to avoid PowerShell encoding/locking quirks
# We use UTF8 without BOM for compatibility with how the bash script writes (and
# what consumers expect).
# We join with `n to ensure Unix-style line endings are used even on Windows.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $False
$Content = [string]::Join("`n", $Lines) + "`n"
[System.IO.File]::WriteAllText($OutputPath, $Content, $Utf8NoBom)

$Acl = Get-Acl $OutputPath
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Read", "Allow")
$Acl.SetAccessRule($AccessRule)
Set-Acl $OutputPath $Acl

exit 0
