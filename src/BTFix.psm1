# BTFix — Bluetooth radio diagnostics and repair engine.
#
# Everything here is side-effect free unless a function explicitly says
# otherwise; the mutating helpers all support -WhatIf via
# SupportsShouldProcess.

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Health.psm1')
Import-Module (Join-Path $PSScriptRoot 'Superiority.psm1') 

$script:BluetoothClassGuid = '{E0CBF06C-CD8B-4647-BB8F-263B43F0C0B74}'

function Write-BTFixLog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'This is a command line tool: progress belongs on the console, not in the pipeline.')]
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
            Write-Verbose "could not write to the log file: $($_.Exception.Message)"
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
        Write-Verbose "property $KeyName is not available for $InstanceId"
    }
    return $null
}

function Test-BTFixInternalRadio {
    <#
    .SYNOPSIS
    Decides whether a radio is built into the machine or is an external dongle.

    .DESCRIPTION
    Windows groups devices that share a physical chassis into a "container".
    An on-board radio shares the container of the computer system
    ({00000000-0000-0000-FFFF-FFFFFFFFFFFF}), while a USB dongle gets its own
    container for the port it is plugged into. Topology alone cannot tell
    them apart, because a built-in radio is also USB-attached internally.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$InstanceId)

    $systemContainer = '{00000000-0000-0000-FFFF-FFFFFFFFFFFF}'
    $container = Get-BTFixProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_ContainerId'
    if ($container) { return ([string]$container).ToUpperInvariant() -eq $systemContainer }

    # Fallback for systems that do not expose a container id: a radio whose
    # parent is a PCI device is on-board.
    $parent = Get-BTFixProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_Parent'
    return [bool]($parent -like 'PCI\*')
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
            IsInternal      = (Test-BTFixInternalRadio -InstanceId $d.InstanceId)
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

<#
.SYNOPSIS
Runs the repair pipeline.
.DESCRIPTION
1. snapshot state
2. restart the Bluetooth stack
3. re-enumerate the broken radio (remove + rescan)
4. if it is still broken and another radio is healthy, disable that one and
   rescan (the stack can only be held by a single radio)
5. verify, and report
#>
function Invoke-BTFixRepair {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [string]$Radio,
        [switch]$PreferInternal,
        [switch]$SearchWindowsUpdate,
        [switch]$DisableUsbSuspend,
        [switch]$ForgetStale,
        [string]$BackupPath,
        [string]$LogPath
    )

    $steps = @()
    $diagnosis = Get-BTFixDiagnosis
    Write-BTFixLog -Message "diagnosis: $($diagnosis.Classification) (confidence $($diagnosis.Confidence))" -Level 'STEP' -Path $LogPath
    foreach ($e in $diagnosis.Evidence) { Write-BTFixLog -Message $e -Path $LogPath }

    if ($diagnosis.Broken.Count -eq 0) {
        Write-BTFixLog -Message 'every radio is healthy - only the optional repairs remain' -Level 'OK' -Path $LogPath
    }

    $backup = New-BTFixBackup -Radios $diagnosis.Radios -BackupPath $BackupPath
    Write-BTFixLog -Message "backup written: $backup" -Level 'OK' -Path $LogPath

    # step 1: make sure the services the stack needs are running
    foreach ($s in (Get-BTFixServiceHealth)) {
        if (-not $s.Present -or $s.Status -eq 'Running') { continue }
        if ($PSCmdlet.ShouldProcess($s.Name, 'Start service')) {
            try {
                Set-Service -Name $s.Name -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service -Name $s.Name -ErrorAction Stop
                Write-BTFixLog -Message "started $($s.Label)" -Level 'OK' -Path $LogPath
                $steps += "started $($s.Name)"
            } catch {
                Write-BTFixLog -Message ("could not start " + $s.Name + ": " + $_.Exception.Message) -Level 'WARN' -Path $LogPath
            }
        }
    }

    # Determine the wanted radio: the one the user pointed at, otherwise
    # the superior radio detected by the Superiority Engine, otherwise the internal adapter.
    $wanted = $null
    if ($Radio) {
        $wanted = $diagnosis.Radios | Where-Object { $_.InstanceId -eq $Radio } | Select-Object -First 1
    }
    if (-not $wanted) {
        if ($PreferInternal) {
            $wanted = $diagnosis.Radios | Where-Object { $_.IsInternal } | Select-Object -First 1
            if (-not $wanted) { $wanted = $diagnosis.Radios | Where-Object { -not $_.IsInternal } | Select-Object -First 1 }
        } else {
            try {
                $sup = Get-BTFixSuperiorRadio -Radios $diagnosis.Radios
                if ($sup -and $sup.SuperiorRadio) {
                    $wanted = $sup.SuperiorRadio
                    Write-BTFixLog -Message "Superiority Engine: selected '$($wanted.FriendlyName)' ($($sup.Reason))" -Level 'INFO' -Path $LogPath
                }
            } catch {
                # fallback
            }
            if (-not $wanted) {
                $wanted = $diagnosis.Radios | Where-Object { -not $_.IsInternal } | Select-Object -First 1
                if (-not $wanted) { $wanted = $diagnosis.Radios | Where-Object { $_.IsInternal } | Select-Object -First 1 }
            }
        }
    }

    # step 2: break any dual-radio conflict before enabling/restarting
    if ($wanted -and (-not $wanted.IsHealthy -or $wanted.IsDisabled)) {
        $conflicting = @($diagnosis.Healthy | Where-Object { $_.InstanceId -ne $wanted.InstanceId })
        foreach ($disable in $conflicting) {
            Write-BTFixLog -Message "disabling conflicting radio: $($disable.FriendlyName)" -Level 'STEP' -Path $LogPath
            if ($PSCmdlet.ShouldProcess($disable.InstanceId, 'Disable radio')) {
                Invoke-BTFixPnp -Arguments @('/disable-device', $disable.InstanceId) -LogPath $LogPath | Out-Null
                $steps += "disabled $($disable.InstanceId)"
            }
        }
    }

    # step 3: enable the wanted radio if it was disabled
    if ($wanted -and $wanted.IsDisabled) {
        Write-BTFixLog -Message "enabling the wanted radio: $($wanted.FriendlyName)" -Level 'STEP' -Path $LogPath
        if ($PSCmdlet.ShouldProcess($wanted.InstanceId, 'Enable radio')) {
            Invoke-BTFixPnp -Arguments @('/enable-device', $wanted.InstanceId) -LogPath $LogPath | Out-Null
            $steps += "enabled $($wanted.InstanceId)"
        }
    }

    # step 4: restart the stack so it releases and re-attaches
    Restart-BTFixStack -LogPath $LogPath
    $steps += 'restarted bthserv'

    # step 5: re-enumerate the broken radio
    foreach ($bad in $diagnosis.Broken) {
        if ($PSCmdlet.ShouldProcess($bad.InstanceId, 'Remove and re-enumerate')) {
            Invoke-BTFixPnp -Arguments @('/remove-device', $bad.InstanceId) -LogPath $LogPath | Out-Null
            $steps += "removed $($bad.InstanceId)"
        }
    }
    Invoke-BTFixRescan -LogPath $LogPath
    $steps += 'rescanned hardware'

    $after = Get-BTFixDiagnosis
    if ($after.Broken.Count -gt 0 -and $after.Healthy.Count -gt 0) {
        # Only one radio can own the Bluetooth stack. The radio the user wants
        # working wins: the one they pointed at, otherwise the external dongle
        # (the thing they just plugged in), otherwise the internal adapter.
        $wanted = $null
        if ($Radio) {
            $wanted = $after.Radios | Where-Object { $_.InstanceId -eq $Radio } | Select-Object -First 1
        }
        if (-not $wanted) {
            $wanted = $after.Radios | Where-Object { -not $_.IsInternal } | Select-Object -First 1
        }
        if (-not $wanted) {
            $wanted = $after.Radios | Where-Object { $_.IsInternal } | Select-Object -First 1
        }

        $brokenIsWanted = $wanted -and ($after.Broken | Where-Object { $_.InstanceId -eq $wanted.InstanceId })
        if ($brokenIsWanted) {
            # the wanted radio is broken and another one holds the stack:
            # park the other one so the wanted radio can take it.
            $disable = $after.Healthy | Where-Object { $_.InstanceId -ne $wanted.InstanceId } | Select-Object -First 1
            if ($disable) {
                Write-BTFixLog -Message "disabling conflicting radio: $($disable.FriendlyName)" -Level 'STEP' -Path $LogPath
                if ($PSCmdlet.ShouldProcess($disable.InstanceId, 'Disable radio')) {
                    Invoke-BTFixPnp -Arguments @('/disable-device', $disable.InstanceId) -LogPath $LogPath | Out-Null
                    $steps += "disabled $($disable.InstanceId)"
                }
                Invoke-BTFixRescan -LogPath $LogPath
                $steps += 'rescanned after conflict break'
            }
        }
        else {
            # the working radio is not the one that is broken: leave it alone
            # and report which one the user should look at.
            $brokenName = ($after.Broken | Select-Object -First 1).FriendlyName
            Write-BTFixLog -Message "the working radio is kept; '$brokenName' stays broken (update its driver or pass -PreferInternal)" -Level 'WARN' -Path $LogPath
            $steps += "kept the working radio; '$brokenName' left as is"
        }
    }

    # a wanted radio that is merely disabled must be switched back on
    foreach ($r in $diagnosis.Radios) {
        if (-not $r.IsDisabled) { continue }
        $isWanted = $false
        if ($Radio) { $isWanted = ($r.InstanceId -eq $Radio) }
        elseif ($PreferInternal) { $isWanted = $r.IsInternal }
        else { $isWanted = (-not $r.IsInternal) }
        if (-not $isWanted) { continue }
        if ($PSCmdlet.ShouldProcess($r.InstanceId, 'Enable radio')) {
            Write-BTFixLog -Message "enabling the wanted radio: $($r.FriendlyName)" -Level 'STEP' -Path $LogPath
            Invoke-BTFixPnp -Arguments @('/enable-device', $r.InstanceId) -LogPath $LogPath | Out-Null
            $steps += "enabled $($r.InstanceId)"
        }
        Invoke-BTFixRescan -LogPath $LogPath
    }

    # step 5 (optional): stop Windows from powering the dongle down
    if ($DisableUsbSuspend) {
        foreach ($r in (Get-BTFixRadio)) {
            if ($r.IsInternal) { continue }
            $power = Get-BTFixUsbPowerSetting -InstanceId $r.InstanceId
            if ($power -and $power.SuspendAllowed) {
                if (Set-BTFixUsbPowerSetting -Setting $power -LogPath $LogPath) {
                    $steps += "disabled USB suspend for $($r.FriendlyName)"
                }
            }
        }
    }

    # step 6 (optional): forget peripherals that are paired but not connected
    if ($ForgetStale) {
        foreach ($p in (Get-BTFixPairedDevice)) {
            if (-not $p.IsNotPresent) { continue }
            if ($PSCmdlet.ShouldProcess($p.FriendlyName, 'Forget paired device')) {
                $removed = Remove-BTFixPairedDevice -Name $p.FriendlyName -LogPath $LogPath
                if ($removed.Count) { $steps += "forgot $($p.FriendlyName)" }
            }
        }
    }

    if ($SearchWindowsUpdate) {
        $steps += (Invoke-BTFixWindowsUpdate -LogPath $LogPath)
    }

    $final = Get-BTFixDiagnosis
    $logContent = if ($LogPath -and (Test-Path -LiteralPath $LogPath)) { Get-Content -LiteralPath $LogPath -Raw } else { '' }
    $rebootNeeded = ($logContent -match 'System reboot is needed|pending system reboot') -or (($final.Radios | ForEach-Object { $_.ProblemCode }) -contains 14)
    $ok = $final.Broken.Count -eq 0

    Write-BTFixLog -Message ("final state: " + $(if ($ok) { 'all radios healthy' } elseif ($rebootNeeded) { 'restart required to complete switch' } else { 'still broken' })) -Level $(if ($ok) { 'OK' } elseif ($rebootNeeded) { 'WARN' } else { 'ERROR' }) -Path $LogPath

    return [pscustomobject]@{
        Changed        = $steps.Count -gt 0
        Healthy        = $ok
        RebootRequired = $rebootNeeded
        Diagnosis      = $final
        Steps          = $steps
        Backup         = $backup
    }
}

<#
.SYNOPSIS
Restores radios that were disabled by a previous repair.
#>
function Invoke-BTFixRollback {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param([string]$BackupPath, [string]$LogPath)

    $backup = Get-BTFixLatestBackup -BackupPath $BackupPath
    $restored = @()

    if ($backup) {
        foreach ($r in $backup.Radios) {
            $live = Get-PnpDevice -InstanceId $r.InstanceId -ErrorAction SilentlyContinue
            $nowDisabled = $live -and ((Get-BTFixProperty -InstanceId $r.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode') -eq 22)
            if (-not $r.IsDisabled -and $nowDisabled) {
                Write-BTFixLog -Message "re-enabling $($r.FriendlyName)" -Level 'STEP' -Path $LogPath
                if ($PSCmdlet.ShouldProcess($r.InstanceId, 'Enable radio')) {
                    Invoke-BTFixPnp -Arguments @('/enable-device', $r.InstanceId) -LogPath $LogPath | Out-Null
                    $restored += $r.InstanceId
                }
            }
        }
    }
    else {
        # No snapshot from a previous run (e.g. the repair was done by hand) —
        # fall back to re-enabling every radio that is currently disabled.
        Write-BTFixLog -Message 'no snapshot found — re-enabling every disabled radio instead' -Level 'WARN' -Path $LogPath
        foreach ($r in (Get-BTFixRadio)) {
            if (-not $r.IsDisabled) { continue }
            Write-BTFixLog -Message "re-enabling $($r.FriendlyName)" -Level 'STEP' -Path $LogPath
            if ($PSCmdlet.ShouldProcess($r.InstanceId, 'Enable radio')) {
                Invoke-BTFixPnp -Arguments @('/enable-device', $r.InstanceId) -LogPath $LogPath | Out-Null
                $restored += $r.InstanceId
            }
        }
    }
    Invoke-BTFixRescan -LogPath $LogPath
    Restart-BTFixStack -LogPath $LogPath
    Write-BTFixLog -Message ("restored: " + ($(if ($restored.Count) { $restored -join ', ' } else { 'nothing to restore' }))) -Level 'OK' -Path $LogPath
    return [pscustomobject]@{ Changed = ($restored.Count -gt 0); Restored = $restored }
}

<#
.SYNOPSIS
Looks for optional drivers on Windows Update (the "Microsoft Update" driver
category) and installs the ones that look Bluetooth related.
#>
function Invoke-BTFixWindowsUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([string]$LogPath)
    $note = 'Windows Update driver search skipped'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'BTFix'
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
        $searcher.ServerSelection = 2
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
        $candidates = @()
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            $u = $result.Updates.Item($i)
            Write-BTFixLog -Message ("candidate driver: " + $u.Title) -Path $LogPath
            if ($u.Title -match 'Bluetooth|CSR|Cambridge|Realtek|Wireless') { $candidates += $u }
        }
        if ($candidates.Count -eq 0) {
            $note = 'Windows Update has no Bluetooth driver for this hardware'
            Write-BTFixLog -Message $note -Level 'WARN' -Path $LogPath
            return $note
        }
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($c in $candidates) { $coll.Add($c) | Out-Null }
        if ($PSCmdlet.ShouldProcess("$($candidates.Count) driver update(s)", 'Download and install')) {
            $downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $coll
            $null = $downloader.Download()
            $installer = $session.CreateUpdateInstaller(); $installer.Updates = $coll
            $r = $installer.Install()
            $note = "installed $($candidates.Count) driver update(s), result $($r.ResultCode)"
        } else {
            $note = "would install $($candidates.Count) driver update(s)"
        }
    } catch {
        $note = 'Windows Update search failed: ' + $_.Exception.Message
        Write-BTFixLog -Message $note -Level 'WARN' -Path $LogPath
    }
    Write-BTFixLog -Message $note -Level 'OK' -Path $LogPath
    return $note
}

<#
.SYNOPSIS
Renders a Markdown diagnostics report (for issues) and writes it to disk.
#>
function Write-BTFixReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$OutputPath,
        [string]$LogPath
    )
    $d = Get-BTFixDiagnosis
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('# BTFix report')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- generated: $((Get-Date).ToString('o'))")
    $null = $sb.AppendLine("- machine: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- windows: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)")
    $null = $sb.AppendLine("- classification: **$($d.Classification)** (confidence $($d.Confidence))")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## Radios')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| radio | status | code | driver | internal |')
    $null = $sb.AppendLine('| --- | --- | --- | --- | --- |')
    foreach ($r in $d.Radios) {
        $null = $sb.AppendLine("| $($r.FriendlyName) | $($r.Status) | $($r.ProblemCode) | $($r.DriverProvider) $($r.DriverVersion) | $($r.IsInternal) |")
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## Evidence')
    $null = $sb.AppendLine()
    foreach ($e in $d.Evidence) { $null = $sb.AppendLine("- $e") }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## Recommended actions')
    $null = $sb.AppendLine()
    foreach ($a in $d.RecommendedActions) { $null = $sb.AppendLine("- $a") }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## Services')
    $null = $sb.AppendLine()
    foreach ($s in (Get-Service bthserv, BTAGService -ErrorAction SilentlyContinue)) {
        $null = $sb.AppendLine("- $($s.Name): $($s.Status) ($($s.StartType))")
    }
    $text = $sb.ToString()
    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $OutputPath -Value $text -Encoding utf8
        Write-BTFixLog -Message "report written: $OutputPath" -Level 'OK' -Path $LogPath
    }
    return $text
}

Export-ModuleMember -Function @(
    'Get-BTFixRadio', 'Get-BTFixDiagnosis', 'New-BTFixBackup', 'Get-BTFixLatestBackup',
    'Invoke-BTFixRepair', 'Invoke-BTFixRollback', 'Invoke-BTFixWindowsUpdate',
    'Write-BTFixReport', 'Write-BTFixLog', 'Test-BTFixAdministrator', 'Get-BTFixStateRoot', 'Test-BTFixInternalRadio',
    'Get-BTFixLmpVersionName', 'Get-BTFixRadioSpecs', 'Get-BTFixRadioScore', 'Get-BTFixSuperiorRadio'
)
