# The CM_PROB_* device problem codes, as defined by Microsoft
# (learn.microsoft.com/windows-hardware/drivers/install/device-manager-error-messages).
#
# Each row carries the official name, how serious it is for a Bluetooth radio
# and what to do about it. The tool uses the table to explain *any* device it
# finds, not just radios.

Set-StrictMode -Version Latest

$script:ProblemCodes = @(
    [pscustomobject]@{ Code = 1;  Name = 'CM_PROB_NOT_CONFIGURED';         Severity = 'High';   Bluetooth = $true;  Summary = 'The device is not configured for the current hardware.'; Fix = 'Re-run the hardware wizard or reinstall the driver.' }
    [pscustomobject]@{ Code = 9;  Name = 'CM_PROB_INVALID_DATA';          Severity = 'Medium'; Bluetooth = $true;  Summary = 'The device reported invalid data.'; Fix = 'Remove and re-enumerate the device; update the driver.' }
    [pscustomobject]@{ Code = 10; Name = 'CM_PROB_FAILED_START';          Severity = 'High';   Bluetooth = $true;  Summary = 'Windows cannot start the driver for this device.'; Fix = 'Try another USB port (USB 2.0), remove + rescan the device, update the driver.' }
    [pscustomobject]@{ Code = 12; Name = 'CM_PROB_NORMAL_CONFLICT';       Severity = 'Low';    Bluetooth = $false; Summary = 'The device is working but is not the preferred device.'; Fix = 'No action needed.' }
    [pscustomobject]@{ Code = 14; Name = 'CM_PROB_NEED_RESTART';          Severity = 'Low';    Bluetooth = $true;  Summary = 'The device needs the computer to be restarted.'; Fix = 'Restart Windows; the device usually starts afterwards.' }
    [pscustomobject]@{ Code = 18; Name = 'CM_PROB_REINSTALL';             Severity = 'Medium'; Bluetooth = $true;  Summary = 'The driver must be reinstalled.'; Fix = 'Remove the device and let Windows install the driver again.' }
    [pscustomobject]@{ Code = 19; Name = 'CM_PROB_REGISTRY';              Severity = 'Medium'; Bluetooth = $true;  Summary = 'The device has a registry problem.'; Fix = 'Reinstall the driver; avoid driver packages from unknown sources.' }
    [pscustomobject]@{ Code = 21; Name = 'CM_PROB_WILL_BE_REMOVED';       Severity = 'Low';    Bluetooth = $true;  Summary = 'The device will be removed at the next restart.'; Fix = 'Reboot to complete the removal.' }
    [pscustomobject]@{ Code = 22; Name = 'CM_PROB_DISABLED';              Severity = 'Info';   Bluetooth = $true;  Summary = 'The device is disabled - this is intentional state, not a failure.'; Fix = 'Enable it again with: .\BTFix.ps1 -Mode Rollback' }
    [pscustomobject]@{ Code = 24; Name = 'CM_PROB_DEVICE_NOT_THERE';      Severity = 'Low';    Bluetooth = $true;  Summary = 'The device is not present.'; Fix = 'Plug the device in, or pair the peripheral again.' }
    [pscustomobject]@{ Code = 28; Name = 'CM_PROB_FAILED_INSTALL';        Severity = 'High';   Bluetooth = $true;  Summary = 'The drivers for this device are not installed (DNF: no compatible driver found).'; Fix = 'Install the vendor driver for this hardware id, or run -SearchWindowsUpdate.' }
    [pscustomobject]@{ Code = 29; Name = 'CM_PROB_HARDWARE_DISABLED';    Severity = 'Info';   Bluetooth = $true;  Summary = 'The device is disabled at the hardware level.'; Fix = 'Enable the device in Device Manager or with pnputil /enable-device.' }
    [pscustomobject]@{ Code = 31; Name = 'CM_PROB_FAILED_ADD';            Severity = 'High';   Bluetooth = $true;  Summary = 'Windows cannot load the drivers required for this device. On Bluetooth dongles this is usually a dual-radio conflict: only one adapter can own the Bluetooth stack.'; Fix = 'Disable the other radio and re-scan; update the driver if the conflict is not the cause.' }
    [pscustomobject]@{ Code = 32; Name = 'CM_PROB_DISABLED_SERVICE';      Severity = 'High';   Bluetooth = $true;  Summary = 'A service needed by the device is disabled.'; Fix = 'Re-enable the Bluetooth Support Service (bthserv) and the device association service.' }
    [pscustomobject]@{ Code = 37; Name = 'CM_PROB_FAILED_DRIVER_ENTRY';   Severity = 'High';   Bluetooth = $true;  Summary = 'The driver failed to initialise.'; Fix = 'Update or reinstall the driver.' }
    [pscustomobject]@{ Code = 38; Name = 'CM_PROB_DRIVER_FAILED_PRIOR_UNLOAD'; Severity = 'High'; Bluetooth = $true; Summary = 'A previous driver could not be unloaded.'; Fix = 'Reboot, then remove and re-add the device.' }
    [pscustomobject]@{ Code = 39; Name = 'CM_PROB_DRIVER_FAILED_LOAD';    Severity = 'High';   Bluetooth = $true;  Summary = 'The driver could not be loaded.'; Fix = 'Update the driver; a reboot is often needed afterwards.' }
    [pscustomobject]@{ Code = 41; Name = 'CM_PROB_LEGACY_SERVICE_NO_DEVICES'; Severity = 'Medium'; Bluetooth = $true; Summary = 'The driver did not report any devices.'; Fix = 'Remove and re-add the device.' }
    [pscustomobject]@{ Code = 42; Name = 'CM_PROB_DUPLICATE_DEVICE';      Severity = 'Medium'; Bluetooth = $true;  Summary = 'The device is installed more than once.'; Fix = 'Remove the duplicate device nodes.' }
    [pscustomobject]@{ Code = 43; Name = 'CM_PROB_FAILED_POST_START';     Severity = 'High';   Bluetooth = $true;  Summary = 'Windows could not start the device.'; Fix = 'Remove + rescan, try another port, update the driver.' }
    [pscustomobject]@{ Code = 45; Name = 'CM_PROB_PHANTOM';               Severity = 'Info';   Bluetooth = $true;  Summary = 'The device is not connected to the computer right now (a paired peripheral that is switched off or out of range).'; Fix = 'Turn the peripheral on; if it stays "not connected", forget it and pair it again.' }
    [pscustomobject]@{ Code = 48; Name = 'CM_PROB_DRIVER_BLOCKED';        Severity = 'High';   Bluetooth = $true;  Summary = 'The driver is blocked by Windows Driver Protection / Memory Integrity because it is known to be incompatible.'; Fix = 'Obtain a newer driver from the hardware vendor; do not disable Memory Integrity.' }
    [pscustomobject]@{ Code = 52; Name = 'CM_PROB_UNSIGNED_DRIVER';       Severity = 'High';   Bluetooth = $true;  Summary = 'The driver is not digitally signed.'; Fix = 'Use a signed driver from the vendor or Windows Update.' }
    [pscustomobject]@{ Code = 54; Name = 'CM_PROB_DEVICE_RESET';         Severity = 'Medium'; Bluetooth = $true;  Summary = 'The device was reset.'; Fix = 'No action usually needed; rescan if it repeats.' }
    [pscustomobject]@{ Code = 56; Name = 'CM_PROB_NEED_CLASS_CONFIG';     Severity = 'Medium'; Bluetooth = $true;  Summary = 'The device class is not configured.'; Fix = 'Reinstall the driver.' }
)

$script:ProblemCodesByName = @{}
foreach ($row in $script:ProblemCodes) {
    $script:ProblemCodesByName[$row.Name] = [int]$row.Code
}

<#
.SYNOPSIS
Returns the numeric problem code for a CM_PROB_* name, or 0 when unknown.
#>
function Get-BTFixProblemCodeByName {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Name)
    if ($script:ProblemCodesByName.ContainsKey($Name)) {
        return $script:ProblemCodesByName[$Name]
    }
    return 0
}

<#
.SYNOPSIS
Returns the problem code row for a numeric code, or $null when unknown.
#>
function Get-BTFixProblemCode {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][int]$Code)
    return ($script:ProblemCodes | Where-Object { $_.Code -eq $Code } | Select-Object -First 1)
}

<#
.SYNOPSIS
Returns every known problem code row.
#>
function Get-BTFixProblemCodeTable {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return $script:ProblemCodes
}

Export-ModuleMember -Function @('Get-BTFixProblemCode', 'Get-BTFixProblemCodeByName', 'Get-BTFixProblemCodeTable')
