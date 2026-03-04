# mkmenu_json.ps1 — Generate a JSON menu file from a menu template.
# Called by mkmenu_json.bat; not intended to be run directly.
param(
    [string]$template,
    [string]$progname,
    [string]$output
)

$lines = Get-Content $template -Encoding UTF8
$menus = @()

$currentMenu = $null
$tab = [char]9

foreach ($raw in $lines) {
    $line = $raw
    $level = 0
    while ($line.Length -gt 0 -and $line[0] -eq $tab) {
        $level++; $line = $line.Substring(1)
    }
    if ($level -eq 0) {
        while ($line.Length -ge 4 -and $line.Substring(0,4) -eq '    ') {
            $level++; $line = $line.Substring(4)
        }
    }
    $line = $line.Trim()
    if ($line -eq '') { continue }
    $line = $line.Replace('{{progname}}', $progname)

    if ($level -eq 0) {
        if ($null -ne $currentMenu) {
            $menus += $currentMenu
        }
        $currentMenu = [ordered]@{
            title = $line
            items = @()
        }
    } else {
        if ($line -eq '-') {
            $currentMenu.items += [ordered]@{ separator = $true }
        } else {
            $currentMenu.items += [ordered]@{ title = $line }
        }
    }
}

if ($null -ne $currentMenu) {
    $menus += $currentMenu
}

# Ensure output directory exists
$outDir = Split-Path -Parent $output
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$json = $menus | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText(
    $output,
    $json,
    [System.Text.UTF8Encoding]::new($false)
)
