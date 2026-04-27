param (
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Output,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$Root
)

Add-Type -AssemblyName System.IO.Compression

$fixedTime = [datetime]"1980-01-01T00:00:00"
$RootFull = (Resolve-Path $Root).Path

$stream = [System.IO.File]::Open($Output, [System.IO.FileMode]::Create)
try {
    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $files = Get-ChildItem -Path $RootFull -Recurse -File
        foreach ($file in $files) {
            # Relativize path and normalize separators
            $relPath = $file.FullName.Substring($RootFull.Length).TrimStart('\', '/')
            $relPath = $relPath -replace '\\', '/'

            $entry = $archive.CreateEntry($relPath, [System.IO.Compression.CompressionLevel]::NoCompression)
            $entry.LastWriteTime = $fixedTime

            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                } finally {
                    $fileStream.Dispose()
                }
            } finally {
                $entryStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
} finally {
    $stream.Dispose()
}

