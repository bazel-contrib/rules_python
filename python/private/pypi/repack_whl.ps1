param(
    [string]$Output
)

$files = Get-ChildItem -Path . -Exclude 'tmp.zip', $Output
Compress-Archive -Path $files -DestinationPath 'tmp.zip' -Force
Move-Item -Path 'tmp.zip' -Destination $Output -Force
