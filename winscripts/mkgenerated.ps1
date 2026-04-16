# mkgenerated.ps1 — Build generated.js and generated.css from framework files.
#
# Usage: mkgenerated.ps1 <menu_template> <progname> <os_name> <theme> <configfile>
#
# Reads boolean flags from <configfile> (usefilesystem, usepassifloraui)
# and concatenates the appropriate JS/CSS framework
# files into src\www\generated\generated.js and generated.css.
param(
    [string]$Template,
    [string]$Progname = "passiflora",
    [string]$OsName = "unknown",
    [string]$Theme = "Default",
    [string]$ConfigFile = "src\config"
)

$ErrorActionPreference = "Stop"

$GeneratedDir = "src\www\generated"
$GeneratedJS  = "$GeneratedDir\generated.js"
$GeneratedCSS = "$GeneratedDir\generated.css"

$PassifloraDir = "src\passiflora"
$PanelsDir     = "src\www\panels"
$VfsDir        = "src\vfs"
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Read feature flags from config ──
$UseFilesystem   = $false
$UsePassifloraUI = $false

if (Test-Path $ConfigFile) {
    foreach ($line in (Get-Content $ConfigFile -Encoding UTF8)) {
        if ($line -match '^usefilesystem\s+true')   { $UseFilesystem   = $true }
        if ($line -match '^usepassifloraui\s+true')  { $UsePassifloraUI = $true }
    }
}

if (-not (Test-Path $GeneratedDir)) { New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null }

# ── Step 1: Generate config.js (PassifloraConfig) into a temp file ──
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mkgen_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

try {
    $ConfigTmp = Join-Path $TmpDir "config.js"
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$ScriptDir\mkmenu_json.ps1" `
        "$Template" "$Progname" "$OsName" "$ConfigTmp" "$Theme" "$ConfigFile"

    # ── Step 2: Build generated.js ──
    $jsContent = [System.Text.StringBuilder]::new()
    [void]$jsContent.Append([System.IO.File]::ReadAllText($ConfigTmp))

    if ($UseFilesystem) {
        # Generate vfspreload.js into temp
        $VfsTmp = Join-Path $TmpDir "vfspreload.js"
        & "$ScriptDir\mkvfspreload.bat" "$VfsDir" "$VfsTmp"
        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText($VfsTmp))

        # Append PassifloraIO.js
        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText("$PassifloraDir\PassifloraIO.js"))
    }

    if ($UsePassifloraUI) {
        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText("$PassifloraDir\UI\fileui.js"))

        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText("$PassifloraDir\UI\buildmenu.js"))

        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText("$PassifloraDir\UI\themes.js"))

        $PanelsTmp = Join-Path $TmpDir "panels.js"
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$ScriptDir\mkpanels.ps1" "$PanelsDir" "$PanelsTmp"
        [void]$jsContent.AppendLine("")
        [void]$jsContent.Append([System.IO.File]::ReadAllText($PanelsTmp))
    }

    [System.IO.File]::WriteAllText($GeneratedJS, $jsContent.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "mkgenerated: $GeneratedJS built"

    # ── Step 3: Build generated.css ──
    $cssContent = [System.Text.StringBuilder]::new()

    if ($UsePassifloraUI) {
        [void]$cssContent.Append([System.IO.File]::ReadAllText("$PassifloraDir\UI\theme.css"))
    }

    [System.IO.File]::WriteAllText($GeneratedCSS, $cssContent.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "mkgenerated: $GeneratedCSS built"
}
finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}
