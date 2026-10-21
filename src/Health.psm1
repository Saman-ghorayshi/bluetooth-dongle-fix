# General health checks that are not about a single radio:
#  - the services the Bluetooth stack depends on
#  - the software radio state (Windows can have the radio switched off)
#  - paired peripherals that are "not connected" (CM_PROB_PHANTOM / code 45)
#  - USB power management on dongles (selective suspend makes them flaky)

Set-StrictMode -Version Latest

$script:BluetoothServices = @(
    [pscustomobject]@{ Name = 'bthserv'; Label = 'Bluetooth Support Service'; Critical = $true }
    [pscustomobject]@{ Name = 'DeviceAssociationService'; Label = 'Device Association Service'; Critical = $false }
    [pscustomobject]@{ Name = 'DeviceInstall'; Label = 'Device Install Service'; Critical = $false }
)

<#
.SYNOPSIS
Returns the state of every service the Bluetooth stack depends on.
#>
function Get-BTFixServiceHealth {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $out = @()
    foreach ($s in $script:BluetoothServices) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        $out += [pscustomobject]@{
            Name      = $s.Name
            Label     = $s.Label
            Critical  = $s.Critical
            Present   = [bool]$svc
            Status    = if ($svc) { [string]$svc.Status } else { 'Missing' }
            StartType = if ($svc) { [string]$svc.StartType } else { '-' }
        }
    }
    return $out
}

<#
.SYNOPSIS
Reads the Windows software radio switch.
.DESCRIPTION
Windows keeps a machine-wide radio switch. When it is off, every Bluetooth
device looks broken even though the driver is fine.
#>
function Get-BTFixRadioSoftwareState {
    [CmdletBinding()]
    [OutputType([object])]
    param()
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Radio Management'
    $value = $null
    try {
        if (Test-Path -LiteralPath $path) {
            $value = (Get-ItemProperty -LiteralPath $path -Name 'SystemRadioState' -ErrorAction SilentlyContinue).SystemRadioState
        }
    } catch {
        $value = $null
    }
    return [pscustomobject]@{
        Path          = $path
        State         = $value
        IsRadioOff    = ($null -ne $value -and [int]$value -eq 1)
        IsRadioOn     = ($null -ne $value -and [int]$value -eq 0)
        Known         = ($null -ne $value)
    }
}

<#
.SYNOPSIS
Lists paired Bluetooth peripherals and whether they are currently connected.
.DESCRIPTION
BTHENUM devices are the peripherals (earbuds, watches, keyboards) Windows has
paired. CM_PROB_PHANTOM (code 45) means "not connected right now" - which is
normal for a device that is switched off, and a real problem when the device
is on and still refuses to connect.
#>
function Get-BTFixPairedDevice {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $out = @()
    foreach ($d in (Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)) {
        if ($d.InstanceId -notlike 'BTHENUM*') { continue }
        $problem = $null
        try {
            $problem = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -ErrorAction SilentlyContinue |
                Where-Object { $_.KeyName -eq 'DEVPKEY_Device_ProblemCode' } | Select-Object -First 1).Data
        } catch {
            $problem = $null
        }
        $code = if ($null -ne $problem) { [int]$problem } else { 0 }
        $out += [pscustomobject]@{
            InstanceId    = $d.InstanceId
            FriendlyName  = $d.FriendlyName
            Status        = [string]$d.Status
            ProblemCode   = $code
            IsConnected   = ([string]$d.Status -eq 'OK' -and $code -eq 0)
            IsNotPresent  = ($code -eq 45)
            IsTransport   = ($d.FriendlyName -like '*Avrcp Transport*')
        }
    }
    return $out
}

<#
.SYNOPSIS
Forgets a paired peripheral so Windows can pair it again.
.DESCRIPTION
Removing the device node clears the stale pairing keys. The peripheral must be
put into pairing mode afterwards.
#>
function Remove-BTFixPairedDevice {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$LogPath
    )
    $removed = @()
    foreach ($p in (Get-BTFixPairedDevice)) {
        if ($p.FriendlyName -notlike "*$Name*" -and $p.InstanceId -notlike "*$Name*") { continue }
        if ($PSCmdlet.ShouldProcess($p.FriendlyName, 'Forget paired device')) {
            $out = & pnputil /remove-device $p.InstanceId 2>&1 | Out-String
            foreach ($line in ($out -split "`r?`n")) {
                if ($line.Trim()) { Write-BTFixLog -Message $line.Trim() -Path $LogPath }
            }
            $removed += $p.InstanceId
        }
    }
    return $removed
}

<#
.SYNOPSIS
Reads or changes the USB power-management flag of a radio.
.DESCRIPTION
"Allow the computer to turn off this device to save power" is stored per USB
device as EnhancedPowerManagementEnabled. With it enabled, cheap dongles drop
out of the Bluetooth stack after a few minutes of idle.
#>
function Get-BTFixUsbPowerSetting {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$InstanceId)

    $parent = $null
    try {
        $parent = (Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue |
            Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Parent' } | Select-Object -First 1).Data
    } catch {
        $parent = $null
    }
    if (-not $parent) { return $null }

    # the radio's USB device node holds the power settings
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$parent\Device Parameters"
    $value = $null
    try {
        if (Test-Path -LiteralPath $regPath) {
            $value = (Get-ItemProperty -LiteralPath $regPath -Name 'EnhancedPowerManagementEnabled' -ErrorAction SilentlyContinue).EnhancedPowerManagementEnabled
        }
    } catch {
        $value = $null
    }
    return [pscustomobject]@{
        InstanceId  = $InstanceId
        Parent      = $parent
        RegistryPath = $regPath
        SuspendAllowed = ($null -eq $value -or [int]$value -ne 0)
        Value       = $value
    }
}

function Set-BTFixUsbPowerSetting {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Setting,
        [switch]$AllowSuspend,
        [string]$LogPath
    )
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'not elevated — cannot change the USB power setting' -Level 'WARN' -Path $LogPath
        return $false
    }
    $value = if ($AllowSuspend) { 1 } else { 0 }
    if ($PSCmdlet.ShouldProcess($Setting.RegistryPath, "Set EnhancedPowerManagementEnabled=$value")) {
        try {
            if (-not (Test-Path -LiteralPath $Setting.RegistryPath)) {
                New-Item -Path $Setting.RegistryPath -Force | Out-Null
            }
            New-ItemProperty -LiteralPath $Setting.RegistryPath -Name 'EnhancedPowerManagementEnabled' -Value $value -PropertyType DWord -Force | Out-Null
            Write-BTFixLog -Message "EnhancedPowerManagementEnabled=$value on $($Setting.Parent)" -Level 'OK' -Path $LogPath
            return $true
        } catch {
            Write-BTFixLog -Message ("could not set the USB power flag: " + $_.Exception.Message) -Level 'WARN' -Path $LogPath
            return $false
        }
    }
    return $false
}

Export-ModuleMember -Function @(
    'Get-BTFixServiceHealth', 'Get-BTFixRadioSoftwareState', 'Get-BTFixPairedDevice',
    'Remove-BTFixPairedDevice', 'Get-BTFixUsbPowerSetting', 'Set-BTFixUsbPowerSetting'
)
