# BTFix — Bluetooth radio diagnostics and repair engine.
#
# Everything here is side-effect free unless a function explicitly says
# otherwise; the mutating helpers all support -WhatIf via
# SupportsShouldProcess.

Set-StrictMode -Version Latest

$script:BluetoothClassGuid = '{E0CBF06C-CD8B-4647-BB8F-263B43F0C0B74}'

function Write-BTFixLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'STEP')][string]$Level = 'INFO',
        [string]$Path
    )
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = '[{0}] {1,-5} {2}' -f $stamp, $Level, $Message
    Write-Host $line
    if ($Path) {
        try {
            Add-Content -LiteralPath $Path -Value $line -Encoding utf8
        } catch {
            # logging must never break the run
        }
    }
}

function Test-BTFixAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BTFixStateRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$BackupPath)
    if ($BackupPath) {
        $resolved = Resolve-Path -LiteralPath $BackupPath -ErrorAction SilentlyContinue
        if ($resolved) { return $resolved.Path }
        return $BackupPath
    }
    return (Join-Path $env:LOCALAPPDATA 'BTFix')
}

function Get-BTFixProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][string]$KeyName
    )
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop |
            Where-Object { $_.KeyName -eq $KeyName } | Select-Object -First 1
        if ($p) { return $p.Data }
    } catch {
        # property may not exist for every device
    }
    return $null
}

function Get-BTFixAncestors {
    <#
    .SYNOPSIS
    Walks a device's parent chain and reports whether it is wired to a PCI
    bus (i.e. an on-board adapter) or to a USB root hub (an external dongle).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [int]$Depth = 4
    )
    $current = Get-BTFixProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_Parent'
    for ($i = 0; $i -lt $Depth -and $current; $i++) {
        if ($current -like 'PCI\*') { return $true }
        $next = Get-BTFixProperty -InstanceId $current -KeyName 'DEVPKEY_Device_Parent'
        if ($next -eq $current) { break }
        $current = $next
    }
    return $false
}

<#
.SYNOPSIS
Enumerates every Bluetooth radio and returns a normalized inventory.
.DESCRIPTION
Radios are USB-attached devices in the Bluetooth device class. Each entry
carries the state the repair engine needs: problem code, driver, and whether
the node is currently disabled.
#>
function Get-BTFixRadio {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$Radio)

    $radios = @()
    foreach ($d in (Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)) {
        if ($d.InstanceId -notlike 'USB\*') { continue }
        if ($Radio -and $d.InstanceId -ne $Radio) { continue }

        $problem = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode'
        $status = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus'
        $driver = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion'
        $provider = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemProvider'
        $ids = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds'
        $loc = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo'
        $parent = Get-BTFixProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Parent'

        $radios += [pscustomobject]@{
            InstanceId      = $d.InstanceId
            FriendlyName    = $d.FriendlyName
            Status          = [string]$d.Status
            ProblemCode     = if ($null -ne $problem) { [int]$problem } else { 0 }
            ProblemStatus   = $status
            DriverVersion   = $driver
            DriverProvider  = $provider
            HardwareIds     = $ids
            LocationInfo    = $loc
            Parent          = $parent
            IsInternal      = (Get-BTFixAncestors -InstanceId $d.InstanceId)
            IsHealthy       = ([string]$d.Status -eq 'OK' -and (-not $problem -or [int]$problem -eq 0))
            IsDisabled      = ([int]$problem -eq 22)
        }
    }
    return $radios
}

<#
.SYNOPSIS
Explains what is wrong with the Bluetooth stack.
.DESCRIPTION
Returns an object with a Classification, a Confidence and a list of
RecommendedActions, plus the evidence the classification was based on.
#>
function Get-BTFixDiagnosis {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        # A mocked inventory (used by the tests). Empty arrays bind as $null in
        # Windows PowerShell, so "no radios at all" is expressed with -NoLive.
        [object[]]$Inventory,
        # Skip the live inventory entirely.
        [switch]$NoLive
    )

    # NOTE: the whole if-expression is wrapped in @() — an if used as an
    # expression unrolls a single-element array into a scalar, which would
    # break .Count under StrictMode.
    $radios = @(if ($NoLive) {
            # no live inventory
        } elseif ($null -ne $Inventory) {
            $Inventory | Where-Object { $null -ne $_ }
        } else {
            Get-BTFixRadio
        })
    $broken = @($radios | Where-Object { -not $_.IsHealthy -and -not $_.IsDisabled })
    $healthy = @($radios | Where-Object { $_.IsHealthy })
    $disabled = @($radios | Where-Object { $_.IsDisabled })

    $actions = @()
    $classification = 'Healthy'
    $confidence = 'High'
    $evidence = @()

    if ($radios.Count -eq 0) {
        $classification = 'NoBluetoothRadio'
        $confidence = 'Medium'
        $evidence += 'No Bluetooth radio was found on this machine.'
        $actions += 'Check that the adapter is plugged in, try another USB port, and that USB ports are enabled in the BIOS/UEFI.'
    }
    elseif ($broken.Count -gt 0) {
        $code = $broken[0].ProblemCode
        if ($code -eq 31) {
            $classification = 'RadioConflictOrDriverStartFailure'
            $evidence += "Radio '$($broken[0].FriendlyName)' ($($broken[0].InstanceId)) fails with Code 31 (CM_PROB_FAILED_ADD)."
            if ($healthy.Count -gt 0) {
                $evidence += "Another radio ($($healthy[0].FriendlyName)) currently holds the Bluetooth stack."
                $confidence = 'High'
                $actions += 'Disable the other radio, re-scan, and let the stack settle on the dongle.'
            } else {
                $confidence = 'Medium'
                $actions += 'Re-enumerate the radio (remove + rescan) and restart the Bluetooth stack.'
                $actions += 'If it still fails, look for a chipset-specific driver (see docs/troubleshooting.md).'
            }
        }
        elseif ($code -eq 28) {
            $classification = 'DriverNotInstalled'
            $evidence += "Radio '$($broken[0].FriendlyName)' has no driver installed (Code 28)."
            $actions += 'Run with -SearchWindowsUpdate, or install the chipset driver from the vendor.'
        }
        elseif ($code -eq 10) {
            $classification = 'DeviceCannotStart'
            $evidence += "Radio '$($broken[0].FriendlyName)' cannot start (Code 10)."
            $actions += 'Try a different USB port (USB 2.0), and remove/rescan the device.'
        }
        else {
            $classification = "RadioProblemCode$code"
            $evidence += "Radio '$($broken[0].FriendlyName)' reports problem code $code."
            $actions += 'Re-enumerate the radio and restart the Bluetooth stack.'
        }
    }
    elseif ($healthy.Count -gt 0) {
        $classification = 'Healthy'
        $evidence += "$($healthy.Count) radio(s) are working."
        if ($disabled.Count -gt 0) {
            $classification = 'HealthyWithDisabledRadio'
            $evidence += "$($disabled.Count) radio(s) are disabled (problem code 22) - that is intentional state, not a failure."
            $actions += 'Re-enable the disabled radio with: .\BTFix.ps1 -Mode Rollback  (or pnputil /enable-device "<instanceId>")'
        }
    }
    else {
        $classification = 'AllRadiosDisabled'
        $confidence = 'High'
        $evidence += "All $($disabled.Count) radio(s) are disabled - Windows has no active Bluetooth adapter."
        $actions += 'Re-enable a radio with: .\BTFix.ps1 -Mode Rollback  (or pnputil /enable-device "<instanceId>")'
    }

    return [pscustomobject]@{
        Classification     = $classification
        Confidence         = $confidence
        Radios             = $radios
        Healthy            = $healthy
        Broken             = $broken
        Disabled           = $disabled
        Evidence           = $evidence
        RecommendedActions = $actions
    }
}

<#
.SYNOPSIS
Creates a snapshot of the current radio state so a repair can be undone.
#>
function New-BTFixBackup {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [object[]]$Radios,
        [string]$BackupPath
    )
    $root = Get-BTFixStateRoot -BackupPath $BackupPath
    $dir = Join-Path $root 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('btfix-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $payload = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString('o')
        Tool      = 'BTFix'
        Radios    = @($Radios | Select-Object InstanceId, FriendlyName, Status, ProblemCode, IsDisabled, IsInternal, HardwareIds)
    }
    if ($PSCmdlet.ShouldProcess($file, 'Write backup')) {
        $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8
    }
    return $file
}

function Get-BTFixLatestBackup {
    [CmdletBinding()]
    [OutputType([object])]
    param([string]$BackupPath)
    $root = Get-BTFixStateRoot -BackupPath $BackupPath
    $dir = Join-Path $root 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $f = Get-ChildItem -LiteralPath $dir -Filter 'btfix-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    return (Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json)
}

function Invoke-BTFixPnp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$LogPath
    )
    $out = & pnputil @Arguments 2>&1 | Out-String
    Write-BTFixLog -Message ("pnputil " + ($Arguments -join ' ')) -Level 'STEP' -Path $LogPath
    foreach ($line in ($out -split "`r?`n")) {
        if ($line.Trim()) { Write-BTFixLog -Message $line.Trim() -Path $LogPath }
    }
    return $out
}

function Restart-BTFixStack {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LogPath)
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'not elevated — skipping service restart' -Level 'WARN' -Path $LogPath
        return
    }
    if ($PSCmdlet.ShouldProcess('Bluetooth Support Service (bthserv)', 'Restart')) {
        try {
            Restart-Service -Name 'bthserv' -Force -ErrorAction Stop
            Write-BTFixLog -Message 'bthserv restarted' -Level 'OK' -Path $LogPath
        } catch {
            Write-BTFixLog -Message ("bthserv restart failed: " + $_.Exception.Message) -Level 'WARN' -Path $LogPath
        }
        Start-Sleep -Seconds 2
    }
}

function Invoke-BTFixRescan {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LogPath)
    if ($PSCmdlet.ShouldProcess('hardware', 'Scan for device changes')) {
        Invoke-BTFixPnp -Arguments @('/scan-devices') -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 5
    }
}

