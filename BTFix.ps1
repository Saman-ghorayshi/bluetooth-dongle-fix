<#
.SYNOPSIS
    BTFix — diagnose and repair USB Bluetooth dongles that Windows refuses to
    start (Code 31 / CM_PROB_FAILED_ADD).

.DESCRIPTION
    Read-only by default. -Mode Repair snapshots the current device state,
    applies the repair pipeline and can be undone with -Mode Rollback.

.EXAMPLE
    .\BTFix.ps1
    Diagnoses the Bluetooth stack and prints the likely cause.

.EXAMPLE
    .\BTFix.ps1 -Mode Repair
    Repairs the broken radio (elevates itself when needed).

.EXAMPLE
    .\BTFix.ps1 -Mode Repair -PreferInternal
    Repairs but keeps the internal adapter active instead of the dongle.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Diagnose', 'Repair', 'Rollback', 'Report')]
    [string]$Mode = 'Diagnose',

    # Only consider this radio (instance id), e.g.
    # USB\VID_0A12&PID_0001\5&5E7D000&0&3
    [string]$Radio,

    # When breaking a dual-radio conflict, keep the internal adapter active.
    [switch]$PreferInternal,

    # Also query Windows Update for an optional driver (slow).
    [switch]$SearchWindowsUpdate,

    # Fail instead of asking for elevation.
    [switch]$NoElevation,

    # Where snapshots are stored (default %LOCALAPPDATA%\BTFix).
    [string]$BackupPath,

    # Write a Markdown diagnostics report here.
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\BTFix.psm1') -Force

# ---------------------------------------------------------------- elevation

function Test-Elevated { Test-BTFixAdministrator }

function Invoke-SelfElevated {
    param([string[]]$Arguments)
    Write-Host 'Administrator rights are required — requesting elevation...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + $Arguments
    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
        return $p.ExitCode
    } catch {
        Write-Host "Elevation was declined or failed: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

$needsAdmin = $Mode -in @('Repair', 'Rollback')
if ($needsAdmin -and -not (Test-Elevated)) {
    if ($NoElevation) {
        Write-Host "Mode '$Mode' needs administrator rights." -ForegroundColor Red
        exit 2
    }
    $forward = @("-Mode $Mode")
    if ($Radio) { $forward += "-Radio `"$Radio`"" }
    if ($PreferInternal) { $forward += '-PreferInternal' }
    if ($SearchWindowsUpdate) { $forward += '-SearchWindowsUpdate' }
    if ($BackupPath) { $forward += "-BackupPath `"$BackupPath`"" }
    if ($ReportPath) { $forward += "-ReportPath `"$ReportPath`"" }
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

# ---------------------------------------------------------------- run

switch ($Mode) {
    'Diagnose' {
        $d = Get-BTFixDiagnosis
        Write-Host ''
        Write-Host 'Bluetooth radios' -ForegroundColor Cyan
        Write-Host '-----------------'
        if ($d.Radios.Count -eq 0) {
            Write-Host '  (no Bluetooth radio found)' -ForegroundColor Yellow
        }
        foreach ($r in $d.Radios) {
            $state = if ($r.IsHealthy) { 'OK' } elseif ($r.IsDisabled) { 'disabled (by us)' } else { "problem code $($r.ProblemCode)" }
            $kind = if ($r.IsInternal) { 'internal' } else { 'external' }
            Write-Host ("  {0,-34} {1,-22} {2,-9} {3}" -f $r.FriendlyName, $r.InstanceId, $kind, $state)
        }
        Write-Host ''
        Write-Host "Classification : $($d.Classification)  (confidence: $($d.Confidence))" -ForegroundColor Cyan
        foreach ($e in $d.Evidence) { Write-Host "  - $e" }
        if ($d.RecommendedActions.Count) {
            Write-Host ''
            Write-Host 'Recommended actions' -ForegroundColor Cyan
            foreach ($a in $d.RecommendedActions) { Write-Host "  - $a" }
        }
        Write-Host ''
        Write-Host 'Run with -Mode Repair to apply the fix (it snapshots first, and can be undone).' -ForegroundColor DarkGray
    }

    'Repair' {
        $result = Invoke-BTFixRepair -Radio $Radio -PreferInternal -SearchWindowsUpdate:$SearchWindowsUpdate -BackupPath $BackupPath -LogPath $LogPath
        Write-Host ''
        foreach ($s in $result.Steps) { Write-Host "  step: $s" -ForegroundColor DarkGray }
        if ($result.Healthy) {
            Write-Host 'Repair succeeded — all radios are healthy.' -ForegroundColor Green
        } else {
            Write-Host 'Repair did not fully succeed. See the log and docs/troubleshooting.md.' -ForegroundColor Yellow
        }
        if ($result.Backup) {
            Write-Host "Snapshot (for rollback): $($result.Backup)" -ForegroundColor DarkGray
        }
    }

    'Rollback' {
        $result = Invoke-BTFixRollback -BackupPath $BackupPath -LogPath $LogPath
        if ($result.Changed) {
            Write-Host ("Restored: " + ($result.Restored -join ', ')) -ForegroundColor Green
        } else {
            Write-Host 'Nothing needed restoring.' -ForegroundColor Yellow
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
