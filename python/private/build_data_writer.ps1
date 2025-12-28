$OutputPath = $env:OUTPUT

Add-Content -Path $OutputPath -Value "TARGET $env:TARGET"
Add-Content -Path $OutputPath -Value "CONFIG_ID $env:CONFIG_ID"
Add-Content -Path $OutputPath -Value "CONFIG_MODE $env:CONFIG_MODE"
Add-Content -Path $OutputPath -Value "STAMPED $env:STAMPED"

$VersionFilePath = $env:VERSION_FILE
if (-not [string]::IsNullOrEmpty($VersionFilePath)) {
    Get-Content -Path $VersionFilePath | Add-Content -Path $OutputPath
}

$InfoFilePath = $env:INFO_FILE
if (-not [string]::IsNullOrEmpty($InfoFilePath)) {
    Get-Content -Path $InfoFilePath | Add-Content -Path $OutputPath
}

exit 0
