<#
.SYNOPSIS
    BTFix — diagnose and repair USB Bluetooth dongles that Windows refuses to
    start (Code 31 / CM_PROB_FAILED_ADD) and the Bluetooth stack problems
    around them.

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
    .\BTFix.ps1 -Mode Forget -Device "QCY-T13"
    Forgets a stale pairing so the earbuds can be paired again.
#>
[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'BTFix is a console tool: coloured progress output belongs on the host, not in the pipeline.')]
param(
    [ValidateSet('Check', 'Diagnose', 'Fix', 'Repair', 'Rollback', 'Report', 'Forget', 'Chipsets')]
    [string]$Mode = 'Check',

    # Restrict the work to this radio (instance id), e.g.
    # USB\VID_0A12&PID_0001\5&5E7D000&0&3
    [string]$Radio,

    # Paired device to forget (name fragment or instance id).
    [string]$Device,

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
Import-Module (Join-Path $PSScriptRoot 'src\BTFix.psm1') -Force

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

$effectiveMode = switch ($Mode) { 'Diagnose' { 'Check' } 'Repair' { 'Fix' } default { $Mode } }
$needsAdmin = $effectiveMode -in @('Fix', 'Rollback', 'Forget')
if ($needsAdmin -and -not (Test-BTFixAdministrator)) {
    if ($NoElevation) {
        Write-Host "Mode '$Mode' needs administrator rights." -ForegroundColor Red
        exit 2
    }
    $forward = @('-Mode', $Mode)
    if ($Radio) { $forward += @('-Radio', $Radio) }
    if ($Device) { $forward += @('-Device', $Device) }
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

function Show-Findings {
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
        $findings = Get-BTFixFinding
        Write-Host ''
        Write-Host 'Bluetooth radios' -ForegroundColor Cyan
        Write-Host '-----------------'
        $radios = @(Get-BTFixRadio)
        if ($radios.Count -eq 0) { Write-Host '  (no Bluetooth radio found)' -ForegroundColor Yellow }
        foreach ($r in $radios) {
            $state = if ($r.IsHealthy) { 'OK' } elseif ($r.IsDisabled) { 'disabled (by us)' } else { "problem code $($r.ProblemCode)" }
            $kind = if ($r.IsInternal) { 'internal' } else { 'external' }
            Write-Host ("  {0,-34} {1,-22} {2,-9} {3}" -f $r.FriendlyName, $r.InstanceId, $kind, $state)
        }
        Write-Host ''
        Write-Host ("Findings ({0})" -f $findings.Count) -ForegroundColor Cyan
        Show-Findings -Findings $findings
        Write-Host ''
        Write-Host 'Run with -Mode Fix to apply the repairs (it snapshots first, and can be undone).' -ForegroundColor DarkGray
    }

    'Fix' {
        $result = Invoke-BTFixRepair -Radio $Radio -PreferInternal -SearchWindowsUpdate:$SearchWindowsUpdate -DisableUsbSuspend:$DisableUsbSuspend -ForgetStale:$ForgetStale -BackupPath $BackupPath -LogPath $LogPath
        Write-Host ''
        foreach ($s in $result.Steps) { Write-Host "  step: $s" -ForegroundColor DarkGray }
        if ($result.Healthy) {
            Write-Host 'All radios are healthy.' -ForegroundColor Green
        } else {
            Write-Host 'Some problems remain. See the log and docs/troubleshooting.md.' -ForegroundColor Yellow
        }
        if ($result.Backup) { Write-Host "Snapshot (for rollback): $($result.Backup)" -ForegroundColor DarkGray }
        Write-Host ''
        Show-Findings -Findings (Get-BTFixFinding)
    }

    'Rollback' {
        $result = Invoke-BTFixRollback -BackupPath $BackupPath -LogPath $LogPath
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
        Write-Host "Report written to $out" -ForegroundColor Green
    }
}

Write-Host ''
Write-Host "log: $LogPath" -ForegroundColor DarkGray
