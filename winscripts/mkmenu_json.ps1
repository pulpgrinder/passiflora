# mkmenu_json.ps1 — Generate config.js with PassifloraConfig from a menu template.
# Called by mkmenu_json.bat; not intended to be run directly.
param(
    [string]$template,
    [string]$progname,
    [string]$osName,
    [string]$output
)

$lines = Get-Content $template -Encoding UTF8

# Recursive function: parse lines starting at $startIdx whose level > $parentLevel
# Returns an array of menu item hashtables, and sets $script:idx to the next unprocessed line.
function Parse-MenuItems {
    param([int]$parentLevel, [array]$allLines, [array]$allLevels)
    $items = @()
    while ($script:idx -lt $allLines.Count) {
        $lvl = $allLevels[$script:idx]
        $txt = $allLines[$script:idx]
        if ($lvl -le $parentLevel) { break }
        $script:idx++
        if ($txt -eq '-') {
            $items += [ordered]@{ separator = $true }
        } else {
            $item = [ordered]@{ title = $txt }
            # Peek: if next line is deeper, recurse for children
            if ($script:idx -lt $allLines.Count -and $allLevels[$script:idx] -gt $lvl) {
                $item['items'] = @(Parse-MenuItems -parentLevel $lvl -allLines $allLines -allLevels $allLevels)
            }
            $items += $item
        }
    }
    return ,$items
}

# First pass: parse all lines into parallel arrays of level + text
$parsedTexts = @()
$parsedLevels = @()
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
    # Items starting with * are native-only; skip from JS output
    if ($line.StartsWith('*')) { continue }
    $parsedTexts += $line
    $parsedLevels += $level
}

# Second pass: build nested structure
$script:idx = 0
$menus = @(Parse-MenuItems -parentLevel -1 -allLines $parsedTexts -allLevels $parsedLevels)

# Ensure output directory exists
$outDir = Split-Path -Parent $output
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$json = $menus | ConvertTo-Json -Depth 10
$header = "// Auto-generated file `u{2014} DO NOT EDIT. This file is overwritten on every build.`n"
$content = $header + "var PassifloraConfig = {`n"
$content += "  os_name: `"$osName`",`n"
$content += "  menus: " + $json + ",`n"
$content += "  handleMenu: function(title) { alert(`"Menu item clicked: `" + title); }`n"
$content += "};`n"
[System.IO.File]::WriteAllText(
    $output,
    $content,
    [System.Text.UTF8Encoding]::new($false)
)
