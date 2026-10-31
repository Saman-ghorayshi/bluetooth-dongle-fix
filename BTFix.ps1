<#
.SYNOPSIS
    BTFix — diagnose and repair USB Bluetooth dongles that Windows refuses to
    start (Code 31 / CM_PROB_FAILED_ADD), resolve 8kHz Hands-Free telephony
    voice traps, monitor BLE peripheral battery levels, optimize A2DP audio
    codecs, and enable esports low-latency controller mode.

.DESCRIPTION
    Read-only by default. -Mode Fix snapshots the current device state,
    applies the repairs that apply and can be undone with -Mode Rollback.

.EXAMPLE
    .\BTFix.ps1
    Runs every check and prints the findings.

.EXAMPLE
    .\BTFix.ps1 -Mode Fix
    Repairs what can be repaired (elevates itself when needed).

.EXAMPLE
    .\BTFix.ps1 -Mode HandsFree -State Disable
    Disables the Hands-Free telephony mic trap to permanently keep Hi-Fi stereo.

.EXAMPLE
    .\BTFix.ps1 -Mode Battery
    Inspects real-time battery percentages and gauges for paired devices.

.EXAMPLE
    .\BTFix.ps1 -Mode Codec -State Enable
    Optimizes A2DP registry settings to unlock AAC and aptX codecs.

.EXAMPLE
    .\BTFix.ps1 -Mode GameMode -State Enable
    Disables USB Selective Suspend to eliminate 50-150ms controller input lag spikes.
#>
[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'BTFix is a console tool: coloured progress output belongs on the host, not in the pipeline.')]
param(
    [ValidateSet('Check', 'Diagnose', 'Fix', 'Repair', 'Rollback', 'Report', 'Forget', 'Chipsets', 'Compare', 'HandsFree', 'Battery', 'Codec', 'GameMode', 'LEAudio', 'Topology', 'UsbTopology')]
    [string]$Mode = 'Check',

    # State for configurable modes (HandsFree, Codec, GameMode, LEAudio)
    [ValidateSet('Disable', 'Enable', 'Status', 'Off', 'On', 'Default')]
    [string]$State = 'Status',

    # Restrict the work to this radio (instance id), e.g.
    # USB\VID_0A12&PID_0001\5&5E7D000&0&3
    [string]$Radio,

    # Paired device to target (name fragment or instance id).
    [string]$Device,

    # Also stop/disable BTAGService (Bluetooth Audio Gateway) in HandsFree mode
    [switch]$ToggleService,

    # When breaking a dual-radio conflict, keep the internal adapter active.
    [switch]$PreferInternal,

    # Also query Windows Update for an optional driver (slow).
    [switch]$SearchWindowsUpdate,

    # Stop Windows from powering down an external dongle.
    [switch]$DisableUsbSuspend,

    # Forget paired peripherals that are not connected.
    [switch]$ForgetStale,

    # Fail instead of asking for elevation.
    [switch]$NoElevation,

    # Where snapshots are stored (default %LOCALAPPDATA%\BTFix).
    [string]$BackupPath,

    # Write a Markdown diagnostics report here.
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Findings.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Health.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Chipsets.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\ProblemCodes.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Superiority.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\BTFix.psm1') -Force

# ---------------------------------------------------------------- integrity

# Every entry point that can run (or elevate) as admin verifies its code files
# first: malware with user rights can rewrite anything under the install dir,
# but not the HKLM baseline recorded by the first elevated run.
$integrity = Test-BTFixIntegrity -ScriptRoot $PSScriptRoot
if (-not $integrity.Ok) {
    Write-Host 'INTEGRITY CHECK FAILED - these files do not match their recorded hashes:' -ForegroundColor Red
    foreach ($m in $integrity.Mismatches) { Write-Host ("  modified: {0}" -f $m) -ForegroundColor Red }
    foreach ($m in $integrity.Missing) { Write-Host ("  missing : {0}" -f $m) -ForegroundColor Red }
    Write-Host 'Refusing to run. Reinstall BTFix, and scan the machine for malware.' -ForegroundColor Red
    exit 3
}
if ($integrity.BaselineSource -eq 'none' -and (Test-BTFixAdministrator)) {
    # First elevated run for this install: lock the baseline into HKLM.
    $null = Save-BTFixIntegrityBaseline -ScriptRoot $PSScriptRoot
}

# An explicit -Radio that matches nothing must not silently fall back to the
# default selection - that selection may disable the radio the user was
# actually pointing at.
if ($Radio) {
    $radioMatch = @(Get-BTFixRadio -Radio $Radio)
    if ($radioMatch.Count -eq 0) {
        Write-Host "No Bluetooth radio matches -Radio '$Radio'." -ForegroundColor Red
        Write-Host 'Run -Mode Check to list the radios and their exact instance ids.' -ForegroundColor Yellow
        exit 2
    }
}

# ---------------------------------------------------------------- elevation

function Invoke-SelfElevated {
    param([string[]]$Arguments)
    Write-Host 'Administrator rights are required - requesting elevation...' -ForegroundColor Yellow
    # -File takes the script path followed by the script's own arguments, one
    # argv entry each (a single "-Mode Fix" string would arrive as one
    # positional argument and the mode would silently stay at its default).
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $Arguments
    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
        return $p.ExitCode
    } catch {
        Write-Host "Elevation was declined or failed: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

$effectiveMode = switch ($Mode) { 'Diagnose' { 'Check' } 'Repair' { 'Fix' } 'UsbTopology' { 'Topology' } default { $Mode } }
$effectiveState = switch ($State) { 'Off' { 'Disable' } 'On' { 'Enable' } default { $State } }
$needsAdmin = ($effectiveMode -in @('Fix', 'Rollback', 'Forget')) -or ($effectiveMode -in @('HandsFree', 'Codec', 'GameMode') -and $effectiveState -ne 'Status')
if ($needsAdmin -and -not (Test-BTFixAdministrator)) {
    if ($NoElevation) {
        Write-Host "Mode '$Mode' needs administrator rights." -ForegroundColor Red
        exit 2
    }
    $forward = @('-Mode', $Mode)
    if ($State) { $forward += @('-State', $State) }
    if ($Radio) { $forward += @('-Radio', $Radio) }
    if ($Device) { $forward += @('-Device', $Device) }
    if ($ToggleService) { $forward += '-ToggleService' }
    if ($PreferInternal) { $forward += '-PreferInternal' }
    if ($SearchWindowsUpdate) { $forward += '-SearchWindowsUpdate' }
    if ($DisableUsbSuspend) { $forward += '-DisableUsbSuspend' }
    if ($ForgetStale) { $forward += '-ForgetStale' }
    if ($BackupPath) { $forward += @('-BackupPath', $BackupPath) }
    if ($ReportPath) { $forward += @('-ReportPath', $ReportPath) }
    if ($WhatIfPreference) { $forward += '-WhatIf' }
    exit (Invoke-SelfElevated -Arguments $forward)
}

# ---------------------------------------------------------------- logging

$root = Get-BTFixStateRoot -BackupPath $BackupPath
$logDir = Join-Path $root 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$LogPath = Join-Path $logDir ('btfix-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

Write-BTFixLog -Message "BTFix $Mode on $env:COMPUTERNAME" -Level 'STEP' -Path $LogPath
Write-BTFixLog -Message ("log: " + $LogPath) -Path $LogPath

function Show-Finding {
    param([object[]]$Findings)
    if (-not $Findings -or $Findings.Count -eq 0) {
        Write-Host 'No problems found - the Bluetooth stack looks healthy.' -ForegroundColor Green
        return
    }
    $color = @{ High = 'Red'; Medium = 'Yellow'; Low = 'DarkGray'; Info = 'DarkGray' }
    foreach ($f in $Findings) {
        Write-Host ''
        Write-Host ("[{0}] {1}" -f $f.Severity.ToUpperInvariant(), $f.Title) -ForegroundColor $color[$f.Severity]
        Write-Host ("  {0}" -f $f.Detail) -ForegroundColor Gray
        Write-Host ("  fix: {0}" -f $f.Fix) -ForegroundColor DarkGray
        if ($f.AutoFixable) { Write-Host '  (BTFix can fix this automatically)' -ForegroundColor DarkCyan }
    }
}

# ---------------------------------------------------------------- run

switch ($effectiveMode) {
    'Check' {
        $findings = Get-BTFixFinding -Radio $Radio -PreferInternal:$PreferInternal
        Write-Host ''
        Write-Host 'Bluetooth radios' -ForegroundColor Cyan
        Write-Host '-----------------'
        $radios = @(Get-BTFixRadio)
        if ($radios.Count -eq 0) { Write-Host '  (no Bluetooth radio found)' -ForegroundColor Yellow }
        foreach ($r in $radios) {
            $radioStateText = if ($r.IsHealthy) { 'OK' } elseif ($r.IsDisabled) { 'disabled (by us)' } else { "problem code $($r.ProblemCode)" }
            $kind = if ($r.IsInternal) { 'internal' } else { 'external' }
            Write-Host ("  {0,-34} {1,-22} {2,-9} {3}" -f $r.FriendlyName, $r.InstanceId, $kind, $radioStateText)
        }
        if ($radios.Count -gt 1) {
            $benchmarkable = @($radios | Where-Object { $_.IsHealthy -or $_.IsDisabled })
            if ($benchmarkable.Count -eq $radios.Count) {
                # A blocked radio never started, so its capability data cannot
                # be read and a benchmark would compare real data against
                # placeholders. Only rank radios that can be benchmarked.
                $comp = Get-BTFixSuperiorRadio -Radios $radios
                Write-Host ''
                Write-Host ("  Superior radio detected: {0} ({1}/100 pts) - run with -Mode Compare for benchmark" -f $comp.SuperiorRadio.FriendlyName, $comp.WinnerScore.Score) -ForegroundColor DarkCyan
            }
        }

        # Bluetooth LE Audio & Auracast Status
        $leCap = Get-BTFixLEAudioCapability -Radios $radios
        if ($leCap.IsSupportedOS) {
            $leStatusText = if ($leCap.RadioSupported) {
                if ($leCap.UserPrefersClassic -eq $true) { 'Disabled (Forced Classic Fallback)' }
                elseif ($leCap.AuracastReady) { 'Ready (LC3 & Auracast broadcast supported)' }
                else { 'Supported (LC3 unicast supported)' }
            } else {
                'Hardware Limited (Requires BT 5.2+ radio)'
            }
            Write-Host ("  Bluetooth LE Audio     : {0} (run -Mode LEAudio for stack details)" -f $leStatusText) -ForegroundColor DarkCyan
        }

        # USB 3.0 / SuperSpeed RF Topology Check for External Dongles
        $topologies = @(Get-BTFixUsbTopology -Radios $radios | Where-Object { $_.IsUsbDongle })
        if ($topologies.Count -gt 0) {
            foreach ($top in $topologies) {
                $rfColor = switch ($top.RfRisk) { 'High' { 'Red' } 'Medium' { 'Yellow' } default { 'Green' } }
                Write-Host ("  USB Port Topology      : {0} [{1} RF Risk] (run -Mode Topology for tree map)" -f $top.PortType, $top.RfRisk) -ForegroundColor $rfColor
            }
        }

        # Paired Peripherals & Battery status
        $peripherals = @(Get-BTFixBatteryStatus)
        if ($peripherals.Count -gt 0) {
            Write-Host ''
            Write-Host 'Paired Peripherals & Battery' -ForegroundColor Cyan
            Write-Host '----------------------------'
            foreach ($p in $peripherals) {
                $connState = if ($p.IsConnected) { 'Connected' } else { 'Not Connected' }
                $batText = if ($p.HasBatteryInfo) { "$($p.BatteryPercent)% $($p.Gauge)" } else { 'No battery telemetry' }
                $color = if ($p.IsConnected) { 'Green' } else { 'DarkGray' }
                Write-Host ("  {0,-34} {1,-14} {2}" -f $p.FriendlyName, $connState, $batText) -ForegroundColor $color
            }
        }

        Write-Host ''
        Write-Host ("Findings ({0})" -f $findings.Count) -ForegroundColor Cyan
        Show-Finding -Findings $findings
        Write-Host ''
        Write-Host 'Run with -Mode Fix to apply the repairs (it snapshots first, and can be undone).' -ForegroundColor DarkGray
    }

    'Fix' {
        $result = Invoke-BTFixRepair -Radio $Radio -PreferInternal:$PreferInternal -SearchWindowsUpdate:$SearchWindowsUpdate -DisableUsbSuspend:$DisableUsbSuspend -ForgetStale:$ForgetStale -BackupPath $BackupPath -LogPath $LogPath
        if ($result.LockFailed) {
            Write-Host 'Another BTFix repair is already running. Wait for it to finish and try again.' -ForegroundColor Red
            exit 2
        }
        Write-Host ''
        foreach ($s in $result.Steps) { Write-Host "  step: $s" -ForegroundColor DarkGray }
        if ($result.Healthy) {
            Write-Host 'All radios are healthy.' -ForegroundColor Green
        } elseif ($result.RebootRequired) {
            Write-Host 'Windows disabled the internal adapter, but a computer restart is required to release the hardware.' -ForegroundColor Yellow
            Write-Host 'Please restart your PC. On boot, the USB dongle will be the only active Bluetooth radio.' -ForegroundColor Cyan
        } else {
            Write-Host 'Some problems remain. See the log and docs/troubleshooting.md.' -ForegroundColor Yellow
        }
        if ($result.Backup) { Write-Host "Snapshot (for rollback): $($result.Backup)" -ForegroundColor DarkGray }
        Write-Host ''
        Show-Finding -Findings (Get-BTFixFinding -Radio $Radio -PreferInternal:$PreferInternal)
    }

    'Rollback' {
        $result = Invoke-BTFixRollback -BackupPath $BackupPath -LogPath $LogPath
        if ($result.LockFailed) {
            Write-Host 'Another BTFix repair is already running. Wait for it to finish and try again.' -ForegroundColor Red
            exit 2
        }
        if ($result.Changed) {
            Write-Host ("Restored: " + ($result.Restored -join ', ')) -ForegroundColor Green
        } else {
            Write-Host 'Nothing needed restoring.' -ForegroundColor Yellow
        }
    }

    'Forget' {
        if (-not $Device) {
            Write-Host 'Give a device name: .\BTFix.ps1 -Mode Forget -Device "QCY-T13"' -ForegroundColor Red
            exit 2
        }
        $removed = Remove-BTFixPairedDevice -Name $Device -LogPath $LogPath
        if ($removed.Count -gt 0) {
            Write-Host ("Forgot: " + ($removed -join ', ')) -ForegroundColor Green
            Write-Host 'Put the device into pairing mode to pair it again.' -ForegroundColor DarkGray
        } else {
            Write-Host "No paired device matching '$Device' was found." -ForegroundColor Yellow
        }
    }

    'HandsFree' {
        Write-Host ''
        Write-Host 'Anti-Handsfree Telephony Hi-Fi Enforcer' -ForegroundColor Cyan
        Write-Host '---------------------------------------' -ForegroundColor Cyan
        $hfDevices = @(Get-BTFixHandsFreeDevice -Name $Device)
        if ($effectiveState -eq 'Status') {
            if ($hfDevices.Count -eq 0) {
                Write-Host 'No Hands-Free telephony audio endpoints found.' -ForegroundColor Yellow
            } else {
                foreach ($d in $hfDevices) {
                    $stateText = if ($d.IsEnabled) { 'ACTIVE (Will trap voice apps to 8kHz mono)' } else { 'DISABLED (Preserving pristine Hi-Fi Stereo)' }
                    $color = if ($d.IsEnabled) { 'Yellow' } else { 'Green' }
                    Write-Host ("  [{0}] {1}" -f $d.Class, $d.FriendlyName) -ForegroundColor White
                    Write-Host ("      State: {0}" -f $stateText) -ForegroundColor $color
                    Write-Host ("      ID   : {0}" -f $d.InstanceId) -ForegroundColor DarkGray
                }
                Write-Host ''
                Write-Host 'To force Hi-Fi stereo and disable telephony mic trap:' -ForegroundColor DarkGray
                Write-Host '  .\BTFix.ps1 -Mode HandsFree -State Disable' -ForegroundColor Cyan
                Write-Host 'To restore Hands-Free telephony mic:' -ForegroundColor DarkGray
                Write-Host '  .\BTFix.ps1 -Mode HandsFree -State Enable' -ForegroundColor Cyan
            }
        } else {
            $res = Set-BTFixHandsFreeState -State $effectiveState -Device $Device -ToggleService:$ToggleService -BackupPath $BackupPath -LogPath $LogPath
            if ($res.Success) {
                Write-Host ("Hands-Free telephony state updated to: {0}" -f $effectiveState) -ForegroundColor Green
                Write-Host ("Affected nodes: {0}" -f ($res.Changed -join ', ')) -ForegroundColor DarkGray
                if ($res.Snapshot) { Write-Host ("State snapshot saved to: {0}" -f $res.Snapshot) -ForegroundColor DarkGray }
            } else {
                Write-Host "Failed to update Hands-Free state: $($res.Error)" -ForegroundColor Red
            }
        }
    }

    'Battery' {
        Write-Host ''
        Write-Host 'Bluetooth Battery Percentage Inspector' -ForegroundColor Cyan
        Write-Host '---------------------------------------' -ForegroundColor Cyan
        $batteries = @(Get-BTFixBatteryStatus -Name $Device)
        if ($batteries.Count -eq 0) {
            Write-Host 'No paired Bluetooth peripherals found.' -ForegroundColor Yellow
        } else {
            foreach ($b in $batteries) {
                $conn = if ($b.IsConnected) { 'Connected' } else { 'Disconnected' }
                $color = if ($b.IsConnected) {
                    if ($b.HasBatteryInfo -and $b.BatteryPercent -le 20) { 'Red' } else { 'Green' }
                } else { 'DarkGray' }
                Write-Host ("  {0,-32} {1,-14} {2}" -f $b.FriendlyName, $conn, $b.Gauge) -ForegroundColor $color
            }
        }
    }

    'Codec' {
        Write-Host ''
        Write-Host 'Bluetooth A2DP Audio Codec Optimizer' -ForegroundColor Cyan
        Write-Host '------------------------------------' -ForegroundColor Cyan
        $codecInfo = Get-BTFixAudioCodecInfo
        Write-Host ("  AAC Codec Support      : {0}" -f $(if ($codecInfo.AacEnabled) { 'ENABLED' } else { 'DISABLED' })) -ForegroundColor $(if ($codecInfo.AacEnabled) { 'Green' } else { 'Yellow' })
        Write-Host ("  aptX Codec Support     : {0}" -f $(if ($codecInfo.AptxEnabled) { 'ENABLED' } else { 'DISABLED' })) -ForegroundColor $(if ($codecInfo.AptxEnabled) { 'Green' } else { 'Yellow' })
        Write-Host ("  Absolute Volume Status : {0}" -f $(if ($codecInfo.AbsoluteVolumeDisabled) { 'DISABLED (Independent volume control)' } else { 'ENABLED (Synced volume)' })) -ForegroundColor White
        
        if ($effectiveState -eq 'Disable') {
            $ok = Set-BTFixAudioCodecPreference -DisableAac -DisableAptx -BackupPath $BackupPath -LogPath $LogPath
            if ($ok) { Write-Host 'High-bitrate codecs disabled (forced SBC baseline).' -ForegroundColor Yellow }
        } elseif ($effectiveState -eq 'Enable') {
            $ok = Set-BTFixAudioCodecPreference -EnableAac -EnableAptx -BackupPath $BackupPath -LogPath $LogPath
            if ($ok) { Write-Host 'High-bitrate codecs enabled (AAC + aptX unlocked).' -ForegroundColor Green }
        } else {
            Write-Host ''
            Write-Host 'To unlock AAC and aptX codecs:' -ForegroundColor DarkGray
            Write-Host '  .\BTFix.ps1 -Mode Codec -State Enable' -ForegroundColor Cyan
        }
    }

    'GameMode' {
        Write-Host ''
        Write-Host 'Gaming Controller Low-Latency Esports Mode' -ForegroundColor Cyan
        Write-Host '------------------------------------------' -ForegroundColor Cyan
        $controllers = @(Get-BTFixGamingController)
        if ($controllers.Count -eq 0) {
            Write-Host 'No gaming controllers (DualSense, Xbox, Switch Pro) currently detected.' -ForegroundColor Yellow
        } else {
            Write-Host ("Detected {0} gaming controller(s):" -f $controllers.Count) -ForegroundColor Green
            foreach ($c in $controllers) {
                Write-Host ("  - {0} ({1}) [{2}] - {3}" -f $c.Model, $c.Vendor, $c.Status, $(if ($c.IsConnected) { 'Connected' } else { 'Disconnected' })) -ForegroundColor White
            }
        }
        if ($effectiveState -eq 'Enable') {
            $res = Optimize-BTFixControllerLatency -BackupPath $BackupPath -LogPath $LogPath
            if ($res.Success) {
                Write-Host 'Esports Mode applied: USB Selective Suspend disabled for all active Bluetooth adapters.' -ForegroundColor Green
                foreach ($a in $res.OptimizedAdapters) { Write-Host ("  + Optimized adapter: {0}" -f $a) -ForegroundColor DarkGray }
            }
        } else {
            Write-Host ''
            Write-Host 'To eliminate USB suspend latency spikes (50-150ms input lag):' -ForegroundColor DarkGray
            Write-Host '  .\BTFix.ps1 -Mode GameMode -State Enable' -ForegroundColor Cyan
        }
    }

    'LEAudio' {
        Write-Host ''
        Write-Host 'Bluetooth LE Audio & LC3 Codec Stack' -ForegroundColor Cyan
        Write-Host '------------------------------------' -ForegroundColor Cyan
        $leInfo = Get-BTFixLEAudioCapability
        
        $osColor = if ($leInfo.IsSupportedOS) { 'Green' } else { 'Yellow' }
        $osLabel = if ($leInfo.Is24H2OrNewer) {
            "Windows 11 Build $($leInfo.WindowsBuild) (24H2+ with Auracast broadcast)"
        } elseif ($leInfo.IsSupportedOS) {
            "Windows 11 Build $($leInfo.WindowsBuild) (LE Audio unicast supported)"
        } else {
            "Build $($leInfo.WindowsBuild) (Windows 11 22H2+ required)"
        }
        Write-Host ("  Operating System       : {0}" -f $osLabel) -ForegroundColor $osColor

        $hwColor = if ($leInfo.RadioSupported) { 'Green' } else { 'Yellow' }
        $hwLabel = if ($leInfo.RadioSupported) {
            "$($leInfo.RadioBtVersion) (LMP $($leInfo.RadioLmpVersion)) - Isochronous Channels (ISOC) supported"
        } else {
            if ($leInfo.RadioLmpVersion) {
                "$($leInfo.RadioBtVersion) (LMP $($leInfo.RadioLmpVersion)) - Hardware limited to BT Classic (LMP 11+ required)"
            } else {
                "Unknown / No active radio"
            }
        }
        Write-Host ("  Radio Hardware Spec    : {0}" -f $hwLabel) -ForegroundColor $hwColor

        $drvColor = if ($leInfo.AudioDriverDetected) { 'Green' } else { 'DarkGray' }
        Write-Host ("  Audio Offload Driver   : {0}" -f $(if ($leInfo.AudioDriverDetected) { 'DETECTED (Intel SST / Realtek LE Audio offload ready)' } else { 'Standard host stack (Offload driver not loaded)' })) -ForegroundColor $drvColor

        $prefColor = if ($leInfo.UserPrefersClassic -eq $false -or ($null -eq $leInfo.UserPrefersClassic -and -not $leInfo.SystemPrefersClassic)) { 'Green' } else { 'Yellow' }
        $prefLabel = if ($leInfo.UserPrefersClassic -eq $false) {
            'PREFERRED (LC3 / BAP enabled by user policy)'
        } elseif ($leInfo.UserPrefersClassic -eq $true) {
            'DISABLED (Forced Classic Audio fallback by user policy)'
        } elseif ($leInfo.SystemPrefersClassic) {
            'DEFAULT (System currently prefers Classic Audio)'
        } else {
            'DEFAULT (LE Audio preferred when capable)'
        }
        Write-Host ("  LE Audio Policy        : {0}" -f $prefLabel) -ForegroundColor $prefColor

        $auraColor = if ($leInfo.AuracastReady) { 'Green' } else { 'DarkGray' }
        Write-Host ("  Auracast Broadcast     : {0}" -f $(if ($leInfo.AuracastReady) { 'READY (BT 5.3+ broadcast hardware)' } else { 'Unavailable (Requires BT 5.3+ and Win 11 23H2+)' })) -ForegroundColor $auraColor

        if ($effectiveState -eq 'Enable') {
            $res = Set-BTFixLEAudioPreference -State Enable -RestartService -BackupPath $BackupPath -LogPath $LogPath
            if ($res.Success) {
                Write-Host 'Bluetooth LE Audio policy updated: UserPrefersClassicAudio=0 (LE Audio preferred).' -ForegroundColor Green
            }
        } elseif ($effectiveState -eq 'Disable') {
            $res = Set-BTFixLEAudioPreference -State Disable -RestartService -BackupPath $BackupPath -LogPath $LogPath
            if ($res.Success) {
                Write-Host 'Bluetooth LE Audio policy updated: UserPrefersClassicAudio=1 (Classic Audio forced).' -ForegroundColor Yellow
            }
        } elseif ($State -eq 'Default') {
            $res = Set-BTFixLEAudioPreference -State Default -RestartService -BackupPath $BackupPath -LogPath $LogPath
            if ($res.Success) {
                Write-Host 'Bluetooth LE Audio policy reverted to default system setting.' -ForegroundColor Green
            }
        } else {
            Write-Host ''
            Write-Host 'To enforce Bluetooth LE Audio (LC3 / Auracast):' -ForegroundColor DarkGray
            Write-Host '  .\BTFix.ps1 -Mode LEAudio -State Enable' -ForegroundColor Cyan
            Write-Host 'To force legacy Classic Audio fallback:' -ForegroundColor DarkGray
            Write-Host '  .\BTFix.ps1 -Mode LEAudio -State Disable' -ForegroundColor Cyan
        }
    }

    'Topology' {
        Write-Host ''
        Write-Host 'USB Port Topology & RF Interference Inspector' -ForegroundColor Cyan
        Write-Host '---------------------------------------------' -ForegroundColor Cyan
        $radios = @(Get-BTFixRadio)
        $topologies = @(Get-BTFixUsbTopology -Radios $radios)
        if ($topologies.Count -eq 0) {
            Write-Host '  (no USB Bluetooth dongles detected)' -ForegroundColor Yellow
        } else {
            foreach ($top in $topologies) {
                $rfColor = switch ($top.RfRisk) { 'High' { 'Red' } 'Medium' { 'Yellow' } default { 'Green' } }
                Write-Host ''
                Write-Host ("  Dongle Radio    : {0}" -f $top.RadioName) -ForegroundColor White
                Write-Host ("  Instance ID     : {0}" -f $top.InstanceId) -ForegroundColor DarkGray
                Write-Host ("  Port Type       : {0}" -f $top.PortType) -ForegroundColor White
                Write-Host ("  Root Hub        : {0}" -f $(if ($top.RootHubId) { $top.RootHubId } else { 'Direct / Unknown' })) -ForegroundColor DarkGray
                Write-Host ("  Host Controller : {0}" -f $(if ($top.HostControllerId) { $top.HostControllerId } else { 'Standard Host Controller' })) -ForegroundColor DarkGray
                Write-Host ("  Adjacent Storage: {0}" -f $(if ($top.HasStorageTraffic) { 'Active USB Storage Device(s) Detected' } else { 'None' })) -ForegroundColor $(if ($top.HasStorageTraffic) { 'Red' } else { 'DarkGray' })
                Write-Host ("  RF Interference : [{0} Risk]" -f $top.RfRisk) -ForegroundColor $rfColor
                Write-Host ("  Diagnosis       : {0}" -f $top.Details) -ForegroundColor Gray
                Write-Host ("  Recommendation  : {0}" -f $top.Recommendation) -ForegroundColor $(if ($top.RfRisk -ne 'Low') { 'Yellow' } else { 'Green' })
            }
        }
    }

    'Chipsets' {
        Write-Host ''
        Write-Host 'Known chipset families' -ForegroundColor Cyan
        foreach ($c in (Get-BTFixChipsetTable)) {
            Write-Host ''
            Write-Host ("  {0}" -f $c.Family) -ForegroundColor White
            Write-Host ("    id    : {0}" -f $c.Pattern) -ForegroundColor DarkGray
            Write-Host ("    vendor: {0}" -f $c.Vendor) -ForegroundColor DarkGray
            Write-Host ("    hint  : {0}" -f $c.DriverHint) -ForegroundColor DarkGray
            if ($c.DriverUrl) { Write-Host ("    driver: {0}" -f $c.DriverUrl) -ForegroundColor DarkCyan }
        }
    }

    'Report' {
        $out = $ReportPath
        if (-not $out) { $out = Join-Path (Get-BTFixStateRoot -BackupPath $BackupPath) ('btfix-report-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
        $text = Write-BTFixReport -OutputPath $out -LogPath $LogPath
        Write-Host $text
        # The JSON twin sits next to the markdown (strip a .md/.markdown/.txt
        # extension if there is one) so tools and issue templates can parse it.
        $jsonOut = [IO.Path]::ChangeExtension($out, '.json')
        $null = Write-BTFixReportJson -OutputPath $jsonOut -LogPath $LogPath
        Write-Host "Report written to $out (+ $jsonOut)" -ForegroundColor Green
    }

    'Compare' {
        $radios = @(Get-BTFixRadio)
        if ($radios.Count -eq 0) {
            Write-Host 'No Bluetooth radios detected.' -ForegroundColor Yellow
        } else {
            Write-Host ''
            Write-Host 'Bluetooth Radio Superiority Benchmark' -ForegroundColor Cyan
            Write-Host '-------------------------------------' -ForegroundColor Cyan
            $comp = Get-BTFixSuperiorRadio -Radios $radios
            foreach ($eval in $comp.Scores) {
                $r = $eval.Radio
                $isSup = ($r.InstanceId -eq $comp.SuperiorRadio.InstanceId)
                $tag = if ($isSup) { '[SUPERIOR *]' } else { '            ' }
                $tagColor = if ($isSup) { 'Green' } else { 'DarkGray' }
                Write-Host ''
                Write-Host ("  {0} {1} ({2})" -f $tag, $r.FriendlyName, $eval.BluetoothVersion) -ForegroundColor $tagColor
                Write-Host ("      Hardware ID : {0}" -f ($r.HardwareIds -join ', ')) -ForegroundColor DarkGray
                Write-Host ("      Placement   : {0}" -f $(if ($r.IsInternal) { 'Internal (Laptop Motherboard)' } else { 'External (USB Dongle)' })) -ForegroundColor White
                Write-Host ("      Total Score : {0}/100" -f $eval.Score) -ForegroundColor $(if ($isSup) { 'Green' } else { 'Yellow' })
                foreach ($fact in $eval.Factors) {
                    Write-Host ("        + {0}" -f $fact) -ForegroundColor DarkGray
                }
            }
            Write-Host ''
            Write-Host "Recommendation: $($comp.Reason)" -ForegroundColor Cyan
        }
    }
}

Write-Host ''
Write-Host "log: $LogPath" -ForegroundColor DarkGray
