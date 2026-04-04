# mkpanels.ps1 — Generate panels.js from HTML/JS files in passiflora\panels.
# Usage: mkpanels.ps1 [panels_dir] [output]
param(
    [string]$PanelsDir = "src\www\passiflora\panels",
    [string]$Output    = "src\www\generated\panels.js"
)

$ErrorActionPreference = "Stop"

# Ensure output directory
$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$htmlFiles = @(Get-ChildItem -Path $PanelsDir -Filter "*.html" -ErrorAction SilentlyContinue)

if ($htmlFiles.Count -eq 0) {
    Set-Content -Path $Output -Value "// Auto-generated `u{2014} no panel files found." -Encoding UTF8
    Write-Host "mkpanels: $Output generated (no panels found in $PanelsDir)"
    exit 0
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("// Auto-generated file `u{2014} DO NOT EDIT. This file is overwritten on every build.")
[void]$sb.AppendLine('(function() {')
[void]$sb.AppendLine('  "use strict";')

foreach ($html in $htmlFiles) {
    $basename = [System.IO.Path]::GetFileNameWithoutExtension($html.Name)
    $raw = [System.IO.File]::ReadAllText($html.FullName)

    # Escape for JS double-quoted string
    $escaped = $raw -replace '\\', '\\' -replace '"', '\"' -replace '</script>', '<\/script>'
    $escaped = $escaped -replace "`r`n", '\n' -replace "`n", '\n' -replace "`r", '\n'

    [void]$sb.AppendLine("  var d = document.createElement(`"div`");")
    [void]$sb.AppendLine("  d.className = `"passiflora_menu_screen`";")
    [void]$sb.AppendLine("  d.id = `"$basename`";")
    [void]$sb.AppendLine("  d.style.display = `"none`";")
    [void]$sb.AppendLine("  d.innerHTML = `"$escaped`";")
    [void]$sb.AppendLine("  document.body.appendChild(d);")
}

[void]$sb.AppendLine('})();')
[void]$sb.AppendLine('')

# Append panel JS files verbatim
$jsFiles = @(Get-ChildItem -Path $PanelsDir -Filter "*.js" -ErrorAction SilentlyContinue)
foreach ($js in $jsFiles) {
    [void]$sb.AppendLine("// --- $($js.Name) ---")
    [void]$sb.Append([System.IO.File]::ReadAllText($js.FullName))
    [void]$sb.AppendLine('')
}

Set-Content -Path $Output -Value $sb.ToString() -Encoding UTF8 -NoNewline
Write-Host "mkpanels: $Output generated from $PanelsDir"
