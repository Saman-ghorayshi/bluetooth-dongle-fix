# The checklist engine: it combines the radio inventory, the Microsoft problem
# code table, the service state, the software radio switch, the paired
# peripherals and the USB power settings into a prioritized list of findings.
#
# Every finding states what is wrong, why it matters and what to do - and
# whether BTFix can fix it on its own.

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProblemCodes.psm1') 
Import-Module (Join-Path $PSScriptRoot 'Chipsets.psm1') 
Import-Module (Join-Path $PSScriptRoot 'Health.psm1') 
Import-Module (Join-Path $PSScriptRoot 'BTFix.psm1') 

<#
.SYNOPSIS
Runs every check and returns the findings, most severe first.
#>
function Get-BTFixFinding {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [object[]]$Inventory,
        [switch]$NoLive,
        [string]$Radio,
        [switch]$PreferInternal
    )

    # An empty array binds as $null in Windows PowerShell, so "no radios at
    # all" is expressed with -NoLive (and an explicit -Inventory @()).
    # The whole if-expression is wrapped in @(): an if used as an expression
    # unrolls a single-element array into a scalar, which breaks .Count.
    $radios = @(if ($null -ne $Inventory) {
            $Inventory | Where-Object { $null -ne $_ }
        } elseif ($NoLive) {
            # deliberately empty
        } else {
            Get-BTFixRadio | ForEach-Object { $_ }
        })
    $findings = @()

    $healthy = @($radios | Where-Object { $_.IsHealthy })
    $broken = @($radios | Where-Object { -not $_.IsHealthy -and -not $_.IsDisabled })
    $disabled = @($radios | Where-Object { $_.IsDisabled })

    # --- no radio at all -------------------------------------------------
    if ($radios.Count -eq 0) {
        $findings += [pscustomobject]@{
            Id = 'no-radio'; Severity = 'High'; Title = 'No Bluetooth radio found'
            Detail = 'Windows does not see a Bluetooth adapter at all - the dongle is not enumerating.'
            Fix = 'Plug the dongle into a USB 2.0 port, try another port, and check that USB ports are enabled in the BIOS/UEFI.'
            AutoFixable = $false
        }
    }

    # --- the classic dongle problem -------------------------------------
    # Which radio does the user want working? The external dongle by default
    # (that is what people plug in), the internal adapter otherwise.
    $wanted = $null
    if ($Radio) {
        $wanted = @($radios | Where-Object { $_.InstanceId -eq $Radio }) | Select-Object -First 1
    }
    if (-not $wanted) {
        $pool = @(if ($PreferInternal) {
                @($radios | Where-Object { $_.IsInternal })
            } else {
                @($radios | Where-Object { -not $_.IsInternal })
            })
        if ($pool.Count -eq 0) {
            $pool = @(if ($PreferInternal) {
                    @($radios | Where-Object { -not $_.IsInternal })
                } else {
                    @($radios | Where-Object { $_.IsInternal })
                })
        }
        if ($pool.Count -gt 0) { $wanted = $pool[0] }
    }

    foreach ($r in $broken) {
        $code = Get-BTFixProblemCode -Code $r.ProblemCode
        $chip = @(Get-BTFixChipset -HardwareId ($r.HardwareIds -join ';')) | Select-Object -First 1
        $detail = "$($r.FriendlyName) [$($r.InstanceId)] reports problem code $($r.ProblemCode)"
        if ($code) { $detail += " ($($code.Name)): $($code.Summary)" }
        $fix = if ($code) { $code.Fix } else { 'Remove the device and re-scan it.' }
        $auto = $false
        $title = "Bluetooth radio is not working (code $($r.ProblemCode))"
        $severity = 'High'

        $isWanted = ($wanted -and $r.InstanceId -eq $wanted.InstanceId)
        if ($isWanted -and $code -and $code.Code -eq 31 -and $healthy.Count -gt 0) {
            $title = 'Two Bluetooth radios are fighting over the stack'
            $detail += " Another radio ($($healthy[0].FriendlyName)) currently owns the Bluetooth stack, and only one adapter can own it at a time."
            $fix = "Disable the other radio and re-scan; the dongle then starts cleanly. (Microsoft's advice for code 31 is to update the driver, but on dongles the conflict is the real cause - see docs/troubleshooting.md.)"
            $auto = $true
        }
        elseif (-not $isWanted -and $healthy.Count -gt 0) {
            # A second radio cannot run while another one owns the stack, so
            # this is the expected consequence of the conflict, not a new fault.
            $severity = 'Info'
            $title = "Radio '$($r.FriendlyName)' is parked while '$($wanted.FriendlyName)' owns the Bluetooth stack"
            $detail = "It reports code $($r.ProblemCode), which is what Windows does to the adapter that does not hold the stack."
            $fix = "Nothing to do - only one Bluetooth radio can own the stack at a time. Run '.\BTFix.ps1 -Mode Fix' if you prefer this one instead."
            $auto = $false
        }
        elseif ($code -and $code.Code -eq 31 -and $healthy.Count -gt 0) {
            $title = 'Two Bluetooth radios are fighting over the stack'
            $detail += " Another radio ($($healthy[0].FriendlyName)) currently owns the Bluetooth stack, and only one adapter can own it at a time."
            $fix = "Disable the other radio and re-scan; the dongle then starts cleanly. (Microsoft's advice for code 31 is to update the driver, but on dongles the conflict is the real cause - see docs/troubleshooting.md.)"
            $auto = $true
        }
        elseif ($code -and $code.Code -eq 28) {
            $title = 'No driver matched this radio'
            if ($chip) { $detail += " Chipset: $($chip.Family). $($chip.DriverHint)" }
            $fix = 'Install the vendor driver for this hardware id, or run .\BTFix.ps1 -Mode Fix -SearchWindowsUpdate.'
        }
        elseif ($code -and $code.Code -eq 48) {
            $title = 'The driver is blocked by Windows Driver Protection'
            $fix = 'Get a newer driver from the hardware vendor. Do not switch off Memory Integrity (HVCI) - that is a security setting.'
        }

        $findings += [pscustomobject]@{
            Id = "radio-$($r.ProblemCode)"; Severity = $severity; Title = $title
            Detail = $detail; Fix = $fix; AutoFixable = $auto
            Data = @{ Radio = $r; ProblemCode = $code; Chipset = $chip; IsWanted = $isWanted }
        }
    }

    # --- a radio that is disabled ---------------------------------------
    foreach ($r in $disabled) {
        $isWanted = ($wanted -and $r.InstanceId -eq $wanted.InstanceId)
        if ($isWanted -and $healthy.Count -gt 0) {
            $findings += [pscustomobject]@{
                Id = 'radio-conflict-disabled'; Severity = 'High'
                Title = "The preferred radio '$($r.FriendlyName)' is disabled while '$($healthy[0].FriendlyName)' is active"
                Detail = "The preferred radio is currently disabled, while another radio owns the Bluetooth stack. Only one radio can own the stack."
                Fix = "Disable '$($healthy[0].FriendlyName)' and enable '$($r.FriendlyName)' with: .\BTFix.ps1 -Mode Fix"
                AutoFixable = $true
                Data = @{ Radio = $r; ConflictingRadio = $healthy[0] }
            }
        } else {
            $findings += [pscustomobject]@{
                Id = 'radio-disabled'; Severity = 'Info'
                Title = "Radio '$($r.FriendlyName)' is disabled"
                Detail = 'A disabled radio is not an error (problem code 22) - it just cannot be used until it is enabled again.'
                Fix = 'Enable it with .\BTFix.ps1 -Mode Rollback.'
                AutoFixable = $true
                Data = @{ Radio = $r }
            }
        }
    }

    if ($NoLive) { return $findings }

    # --- services --------------------------------------------------------
    foreach ($s in (Get-BTFixServiceHealth)) {
        if (-not $s.Present) {
            $findings += [pscustomobject]@{
                Id = "service-missing-$($s.Name)"; Severity = 'High'
                Title = "$($s.Label) is missing"
                Detail = 'The service was not found on this system.'
                Fix = 'Repair the Windows Bluetooth feature (Settings > Optional features, or DISM /Online /Cleanup-Image /RestoreHealth).'
                AutoFixable = $false
            }
            continue
        }
        if ($s.Status -ne 'Running') {
            $findings += [pscustomobject]@{
                Id = "service-stopped-$($s.Name)"; Severity = $(if ($s.Critical) { 'High' } else { 'Low' })
                Title = "$($s.Label) is not running"
                Detail = "Status: $($s.Status) (start type: $($s.StartType))."
                Fix = 'Start the service, and let the Bluetooth stack re-enumerate the radios.'
                AutoFixable = $true
                Data = @{ Service = $s }
            }
        }
        if ($s.StartType -eq 'Disabled') {
            $findings += [pscustomobject]@{
                Id = "service-disabled-$($s.Name)"; Severity = 'High'
                Title = "$($s.Label) is disabled"
                Detail = 'The service start type is Disabled, so Bluetooth cannot work until it is changed.'
                Fix = 'Set the service to Manual and start it.'
                AutoFixable = $true
                Data = @{ Service = $s }
            }
        }
    }

    # --- the software radio switch --------------------------------------
    $radioState = Get-BTFixRadioSoftwareState
    if ($radioState.IsRadioOff) {
        $findings += [pscustomobject]@{
            Id = 'radio-software-off'; Severity = 'High'
            Title = 'The Bluetooth radio is switched off in software'
            Detail = 'Windows keeps a machine-wide radio switch. While it is off, every Bluetooth device looks broken.'
            Fix = 'Turn the radio back on: Settings > Network & internet > Bluetooth, or press the Fn/F11 radio key.'
            AutoFixable = $false
        }
    }

    # --- paired peripherals that are not connected -----------------------
    $paired = @(Get-BTFixPairedDevice)
    $stale = @($paired | Where-Object { $_.IsNotPresent })
    if ($stale.Count -gt 0) {
        $names = ($stale | ForEach-Object { $_.FriendlyName } | Select-Object -Unique) -join ', '
        $findings += [pscustomobject]@{
            Id = 'paired-not-connected'; Severity = 'Info'
            Title = "$($stale.Count) paired device(s) are not connected right now"
            Detail = "Not-connected (code 45) entries: $names. This is normal for peripherals that are switched off or out of range."
            Fix = 'Turn the peripheral on. If it stays "not connected", forget it and pair it again: .\BTFix.ps1 -Mode Forget -Device <name>'
            AutoFixable = $true
            Data = @{ Stale = $stale }
        }
    }

    # --- USB power management on dongles --------------------------------
    foreach ($r in $radios) {
        if ($r.IsInternal) { continue }
        $power = Get-BTFixUsbPowerSetting -InstanceId $r.InstanceId
        if ($power -and $power.SuspendAllowed) {
            $findings += [pscustomobject]@{
                Id = 'usb-suspend'; Severity = 'Low'
                Title = "The dongle may be powered down by Windows"
                Detail = "USB selective suspend is allowed for $($r.FriendlyName). Cheap dongles then drop out of the Bluetooth stack after a few minutes of idle."
                Fix = 'Allow the computer to turn off this device to save power: uncheck it in Device Manager > Properties > Power Management (or run .\BTFix.ps1 -Mode Fix -DisableUsbSuspend).'
                AutoFixable = $true
                Data = @{ Radio = $r; Power = $power }
            }
        }
    }

    $order = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    return @($findings | Sort-Object -Property @{ Expression = { $order[$_.Severity] } }, Title)
}

Export-ModuleMember -Function @('Get-BTFixFinding')
