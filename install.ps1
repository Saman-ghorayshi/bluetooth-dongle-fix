<#
.SYNOPSIS
    One-Line Web Installer & Runner for Bluetooth Dongle Fix (BTFix)
.DESCRIPTION
    Installs BTFix directly from GitHub without needing Git or manual zip extraction:
        irm https://raw.githubusercontent.com/Saman-ghorayshi/bluetooth-dongle-fix/main/install.ps1 | iex
.PARAMETER InstallDir
    Target directory (default: %LOCALAPPDATA%\BTFix)
.PARAMETER LaunchGui
    Launch the graphical interface immediately after installation.
.PARAMETER NoShortcut
    Do not create Desktop or Start Menu shortcuts.
.PARAMETER Uninstall
    Remove BTFix, shortcuts, and PATH registrations from the system.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'BTFix'),
    [switch]$NoGui,
    [switch]$NoShortcut,
    [switch]$Uninstall,
    [string]$Branch = 'main',
    # Pin the install to a release tag (e.g. 'v1.2.0') instead of a branch.
    # Tagged releases ship a file-hashes.json manifest that every downloaded
    # file is verified against before the install completes.
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$repoBase = if ($Version) {
    "https://raw.githubusercontent.com/Saman-ghorayshi/bluetooth-dongle-fix/$Version"
} else {
    "https://raw.githubusercontent.com/Saman-ghorayshi/bluetooth-dongle-fix/$Branch"
}

# Windows PowerShell 5.1 on older Windows 10 builds defaults to TLS 1.0 and
# cannot negotiate github.com without this line.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ----------------- Uninstallation -----------------
if ($Uninstall) {
    Write-Host "`n=== Uninstalling Bluetooth Dongle Fix (BTFix) ===" -ForegroundColor Yellow

    # Remove Desktop shortcut
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Bluetooth Dongle Fix.lnk'
    if (Test-Path -LiteralPath $desktopShortcut) {
        Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
        Write-Host "Removed desktop shortcut: $desktopShortcut" -ForegroundColor Gray
    }

    # Remove Start Menu shortcut
    $programsPath = [Environment]::GetFolderPath('Programs')
    $startMenuShortcut = Join-Path $programsPath 'Bluetooth Dongle Fix.lnk'
    if (Test-Path -LiteralPath $startMenuShortcut) {
        Remove-Item -LiteralPath $startMenuShortcut -Force -ErrorAction SilentlyContinue
        Write-Host "Removed Start Menu shortcut: $startMenuShortcut" -ForegroundColor Gray
    }

    # Remove from User PATH
    $binDir = Join-Path $InstallDir 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -and ($userPath -split ';' -contains $binDir)) {
        $newPath = (($userPath -split ';') | Where-Object { $_ -ne $binDir }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "Removed '$binDir' from User PATH." -ForegroundColor Gray
    }

    # Remove program files, but keep backups and logs: the snapshots are the
    # only way to undo a repair, so deleting them silently would strand any
    # radio BTFix parked. The user can delete the folder manually if they
    # really want everything gone.
    foreach ($sub in @('bin', 'src', 'BTFix.ps1', 'BTFix-GUI.ps1', 'BTFix-GUI.bat', 'BTFix.bat', 'Run-Fix-As-Admin.bat')) {
        $target = Join-Path $InstallDir $sub
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Removed program files under: $InstallDir" -ForegroundColor Gray
    if (Test-Path -LiteralPath (Join-Path $InstallDir 'backups')) {
        Write-Host "Kept snapshots and logs under $InstallDir (delete the folder manually if you do not need them)." -ForegroundColor Yellow
    }

    Write-Host "Uninstallation complete!`n" -ForegroundColor Green
    return
}

# ----------------- Installation -----------------

Write-Host @"

  ____ _____ _____ _       
 | __ )_   _|  ___(_)_  __ 
 |  _ \ | | | |_  | \ \/ / 
 | |_) || | |  _| | |>  <  
 |____/ |_| |_|   |_/_/\_\ 
 Bluetooth Dongle Fix & Benchmark Suite
 Windows 10 & 11 Dual-Radio Conflict Resolver

"@ -ForegroundColor Cyan

Write-Host "Installing to: $InstallDir" -ForegroundColor Gray

$binDir = Join-Path $InstallDir 'bin'
$srcDir = Join-Path $InstallDir 'src'
$backupDir = Join-Path $InstallDir 'backups'
$logDir = Join-Path $InstallDir 'logs'

foreach ($d in @($InstallDir, $binDir, $srcDir, $backupDir, $logDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$filesToDownload = @(
    'BTFix.ps1',
    'BTFix-GUI.ps1',
    'BTFix-GUI.bat',
    'BTFix.bat',
    'Run-Fix-As-Admin.bat',
    'src/BTFix.psd1',
    'src/BTFix.psm1',
    'src/Chipsets.psm1',
    'src/Findings.psm1',
    'src/Health.psm1',
    'src/ProblemCodes.psm1',
    'src/Superiority.psm1'
)

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'BTFix-Installer')

foreach ($rel in $filesToDownload) {
    $remoteUrl = "$repoBase/$rel"
    $localFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
    $targetFolder = Split-Path -Parent $localFile
    if (-not (Test-Path -LiteralPath $targetFolder)) {
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    }

    Write-Host "  -> Fetching $rel..." -ForegroundColor DarkGray
    try {
        $wc.DownloadFile($remoteUrl, $localFile)
    } catch {
        Write-Host "Warning: Could not download $rel from GitHub ($($_.Exception.Message))." -ForegroundColor Yellow
    }
}

# A partial install leaves shortcuts and PATH entries pointing at missing
# files - refuse to finish when anything core is missing.
$missing = @($filesToDownload | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallDir ($_ -replace '/', '\'))) })
if ($missing.Count -gt 0) {
    Write-Host "Installation FAILED: these files could not be downloaded: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Check your internet connection (and that branch '$Branch' exists), then re-run the installer." -ForegroundColor Red
    exit 1
}

# Verify the downloaded files against the release's own hash manifest when
# one exists (tagged releases ship file-hashes.json). A mismatch means the
# download is not what the release shipped - refuse to finish.
try {
    $remoteManifest = Join-Path $env:TEMP ("btfix-manifest-" + [guid]::NewGuid().ToString('N') + ".json")
    $wc.DownloadFile("$repoBase/file-hashes.json", $remoteManifest)
    $manifest = Get-Content -LiteralPath $remoteManifest -Raw | ConvertFrom-Json
    $bad = @()
    foreach ($prop in $manifest.PSObject.Properties) {
        $localFile = Join-Path $InstallDir ($prop.Name.Replace('/', '\'))
        if (Test-Path -LiteralPath $localFile) {
            if ((Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash -ne $prop.Value) {
                $bad += $prop.Name
            }
        } else {
            $bad += "$($prop.Name) (missing)"
        }
    }
    Remove-Item -LiteralPath $remoteManifest -Force -ErrorAction SilentlyContinue
    if ($bad.Count -gt 0) {
        Write-Host "Installation FAILED: integrity check failed for: $($bad -join ', ')" -ForegroundColor Red
        Write-Host 'The downloaded files do not match the release manifest. Do not run them; re-download or pin a release with -Version.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Verified every file against the release hash manifest.' -ForegroundColor DarkGray
} catch {
    Write-Host 'Note: no hash manifest at the requested branch/tag - skipping release verification.' -ForegroundColor DarkGray
}

# Record the SHA256 of every code file as the integrity baseline. It lives in
# HKLM once the first elevated run happens; this advisory JSON is the
# reference until then. Key names use backslash paths to match the module's
# own integrity file list.
$hashes = [ordered]@{}
foreach ($rel in $filesToDownload) {
    $localFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
    if (Test-Path -LiteralPath $localFile) {
        $hashes[$rel.Replace('/', '\')] = (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash
    }
}
try {
    $hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $InstallDir 'file-hashes.json') -Encoding utf8
    Write-Host "Recorded integrity baseline (file-hashes.json)." -ForegroundColor DarkGray
} catch {
    Write-Host "Notice: could not write the integrity baseline ($($_.Exception.Message))" -ForegroundColor Gray
}

# Generate CMD wrappers in bin directory
$btfixCmd = Join-Path $binDir 'btfix.cmd'
Set-Content -LiteralPath $btfixCmd -Value "@powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\BTFix.ps1`" %*" -Encoding ASCII

$btfixGuiCmd = Join-Path $binDir 'btfix-gui.cmd'
Set-Content -LiteralPath $btfixGuiCmd -Value "@powershell -NoProfile -ExecutionPolicy Bypass -STA -File `"%~dp0..\BTFix-GUI.ps1`" %*" -Encoding ASCII

# Register bin in User PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$pathEntries = $userPath -split ';' | Where-Object { $_ -ne '' }
if ($pathEntries -notcontains $binDir) {
    $newUserPath = ($pathEntries + $binDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    $env:Path = "$env:Path;$binDir"
    Write-Host "Added '$binDir' to User PATH (command 'btfix' is now available everywhere)." -ForegroundColor Green
}

# Create Shortcuts
if (-not $NoShortcut) {
    try {
        $wsh = New-Object -ComObject WScript.Shell

        # Desktop Shortcut
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $desktopLnk = Join-Path $desktopPath 'Bluetooth Dongle Fix.lnk'
        $shortcut = $wsh.CreateShortcut($desktopLnk)
        $shortcut.TargetPath = Join-Path $InstallDir 'BTFix-GUI.bat'
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.Description = 'Bluetooth Dongle Fix & Superiority Benchmark'
        $shortcut.IconLocation = 'shell32.dll,207' # Bluetooth/Network icon
        $shortcut.Save()
        Write-Host "Created Desktop shortcut: $desktopLnk" -ForegroundColor Green

        # Start Menu Shortcut
        $programsPath = [Environment]::GetFolderPath('Programs')
        $startMenuLnk = Join-Path $programsPath 'Bluetooth Dongle Fix.lnk'
        $shortcutStart = $wsh.CreateShortcut($startMenuLnk)
        $shortcutStart.TargetPath = Join-Path $InstallDir 'BTFix-GUI.bat'
        $shortcutStart.WorkingDirectory = $InstallDir
        $shortcutStart.Description = 'Bluetooth Dongle Fix & Superiority Benchmark'
        $shortcutStart.IconLocation = 'shell32.dll,207'
        $shortcutStart.Save()
        Write-Host "Created Start Menu shortcut." -ForegroundColor Green
    } catch {
        Write-Host "Notice: Shortcut creation skipped ($($_.Exception.Message))" -ForegroundColor Gray
    }
}

Write-Host @"

===================================================================
  SUCCESS: Bluetooth Dongle Fix is installed and ready to use!
===================================================================
  CLI usage : btfix (or btfix -Mode Fix)
  GUI usage : btfix-gui (or double-click desktop shortcut)
===================================================================
"@ -ForegroundColor Cyan

if (-not $NoGui) {
    $guiBat = Join-Path $InstallDir 'BTFix-GUI.bat'
    if (Test-Path -LiteralPath $guiBat) {
        Write-Host "Launching Graphical Interface..." -ForegroundColor Green
        Start-Process -FilePath $guiBat
    }
}
