# mkzipfile.ps1 — Embed a directory of files as a ZIP for the native server.
# Called by mkzipfile.bat. Requires PowerShell 5+.
param(
    [Parameter(Mandatory = $true)][string]$SrcDir,
    [Parameter(Mandatory = $true)][string]$DestZip
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = (Resolve-Path $SrcDir).Path
$media = @('.mp4', '.jpg', '.jpeg', '.png', '.webp', '.ttf', '.woff', '.woff2')

if (Test-Path $DestZip) { Remove-Item -Force $DestZip }

$zip = [System.IO.Compression.ZipFile]::Open($DestZip, 'Create')
try {
    Get-ChildItem -Path $src -Recurse -File |
        Where-Object { $_.Name -notlike '.*' } |
        ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/').Replace('\', '/')
            $ext = [IO.Path]::GetExtension($_.Name).ToLowerInvariant()
            $level = if ($media -contains $ext) {
                [System.IO.Compression.CompressionLevel]::NoCompression
            } else {
                [System.IO.Compression.CompressionLevel]::Optimal
            }
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $rel, $level)
        }
}
finally {
    $zip.Dispose()
}

# Validate: no empty payloads for non-empty sources; media must be stored.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($DestZip)
$bad = New-Object System.Collections.Generic.List[string]
$deflated = New-Object System.Collections.Generic.List[string]
try {
    foreach ($e in $z.Entries) {
        if ([string]::IsNullOrEmpty($e.Name)) { continue }
        $diskPath = Join-Path $src ($e.FullName -replace '/', '\')
        if (-not (Test-Path -LiteralPath $diskPath)) { continue }
        $disk = (Get-Item -LiteralPath $diskPath).Length
        if ($disk -gt 0 -and $e.Length -eq 0) {
            [void]$bad.Add($e.FullName)
        }
        $ext = [IO.Path]::GetExtension($e.Name).ToLowerInvariant()
        # Stored entries have CompressedLength == Length (plus negligible overhead can differ;
        # NoCompression still reports method implicitly via equal sizes in practice).
        # Prefer checking via ZipFile in Python when available; otherwise size heuristic.
        if (($media -contains $ext) -and ($e.Length -gt 0) -and ($e.CompressedLength -gt 0) `
            -and ($e.CompressedLength + 64 -lt $e.Length)) {
            [void]$deflated.Add($e.FullName)
        }
    }
}
finally {
    $z.Dispose()
}

if ($bad.Count -gt 0) {
    Write-Error ("mkzipfile: ERROR — zip stored empty data for non-empty files:`n  " + ($bad -join "`n  "))
    exit 1
}

# Authoritative compress_type check when Python is available
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $code = @'
import sys, zipfile
from pathlib import Path
z = zipfile.ZipFile(sys.argv[1])
media = {'.mp4', '.jpg', '.jpeg', '.png', '.webp', '.ttf', '.woff', '.woff2'}
bad = []
empty = []
for i in z.infolist():
    if i.is_dir():
        continue
    ext = Path(i.filename).suffix.lower()
    if ext in media and i.compress_type != zipfile.ZIP_STORED:
        bad.append(i.filename)
with zipfile.ZipFile(sys.argv[1]) as z2:
    pass
if bad:
    print("mkzipfile: ERROR — media should be ZIP stored (method 0), not deflated:", file=sys.stderr)
    for n in bad[:20]:
        print("  " + n, file=sys.stderr)
    sys.exit(1)
print("mkzipfile: zip content check OK (media stored uncompressed)")
'@
    $code | & $python.Source - $DestZip
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} elseif ($deflated.Count -gt 0) {
    Write-Error ("mkzipfile: ERROR — media appears deflated (install Python for exact check):`n  " + ($deflated -join "`n  "))
    exit 1
} else {
    Write-Host "mkzipfile: zip content check OK"
}
