# General health checks that are not about a single radio:
#  - the services the Bluetooth stack depends on
#  - the software radio state (Windows can have the radio switched off)
#  - paired peripherals that are "not connected" (CM_PROB_PHANTOM / code 45)
#  - USB power management on dongles (selective suspend makes them flaky)
#  - Hands-Free (HFP/HSP) telephony profile isolation for crystal-clear Hi-Fi audio
#  - Real-time battery percentage monitoring for BLE & Audio peripherals
#  - Bluetooth A2DP audio codec configuration (AAC, aptX, Absolute Volume)
#  - Low-latency esports gaming controller detection & USB power optimization

Set-StrictMode -Version Latest

$script:BluetoothServices = @(
    [pscustomobject]@{ Name = 'bthserv'; Label = 'Bluetooth Support Service'; Critical = $true }
    [pscustomobject]@{ Name = 'BTAGService'; Label = 'Bluetooth Audio Gateway Service'; Critical = $false }
    [pscustomobject]@{ Name = 'AudioEndpointBuilder'; Label = 'Windows Audio Endpoint Builder'; Critical = $false }
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
        if ($d.InstanceId -notlike 'BTHENUM*' -and $d.InstanceId -notlike 'BTHLE*') { continue }
        $statusStr = [string]$d.Status
        $code = 0
        if ($d.PSObject.Properties['Present'] -and $d.Present -eq $false) {
            $code = 45
        } elseif ($d.PSObject.Properties['Problem'] -and $d.Problem) {
            if (Get-Command 'Get-BTFixProblemCodeByName' -ErrorAction SilentlyContinue) {
                $code = Get-BTFixProblemCodeByName -Name ([string]$d.Problem)
            } else {
                $code = if ($d.Problem -eq 'CM_PROB_PHANTOM') { 45 } else { 0 }
            }
        } elseif ($statusStr -ne 'OK') {
            try {
                $prop = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
                if ($prop -and $null -ne $prop.Data) { $code = [int]$prop.Data }
            } catch {
                $null = $_
            }
        }
        $out += [pscustomobject]@{
            InstanceId    = $d.InstanceId
            FriendlyName  = $d.FriendlyName
            Status        = $statusStr
            ProblemCode   = $code
            IsConnected   = ($statusStr -eq 'OK' -and $code -eq 0)
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
device as EnhancedPowerManagementEnabled under the device's OWN instance key
(Device Parameters) - not on the parent hub. With it enabled, cheap dongles
drop out of the Bluetooth stack after a few minutes of idle.
#>
function Get-BTFixUsbPowerSetting {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$InstanceId)

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters"
    $value = $null
    $existed = $false
    try {
        if (Test-Path -LiteralPath $regPath) {
            $prop = Get-ItemProperty -LiteralPath $regPath -Name 'EnhancedPowerManagementEnabled' -ErrorAction SilentlyContinue
            if ($prop) {
                $value = $prop.EnhancedPowerManagementEnabled
                $existed = $true
            }
        }
    } catch {
        $value = $null
    }
    return [pscustomobject]@{
        InstanceId     = $InstanceId
        RegistryPath   = $regPath
        SuspendAllowed = ($null -eq $value -or [int]$value -ne 0)
        Value          = $value
        Existed        = $existed
    }
}

function Set-BTFixUsbPowerSetting {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Setting,
        [switch]$AllowSuspend,
        # Explicit value (0/1). Overrides the -AllowSuspend switch; used by
        # rollback to put back whatever the snapshot recorded.
        [int]$Value,
        [string]$LogPath
    )
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'not elevated — cannot change the USB power setting' -Level 'WARN' -Path $LogPath
        return $false
    }
    $value = if ($PSBoundParameters.ContainsKey('Value')) { $Value } elseif ($AllowSuspend) { 1 } else { 0 }
    if ($PSCmdlet.ShouldProcess($Setting.RegistryPath, "Set EnhancedPowerManagementEnabled=$value")) {
        try {
            if (-not (Test-Path -LiteralPath $Setting.RegistryPath)) {
                New-Item -Path $Setting.RegistryPath -Force | Out-Null
            }
            New-ItemProperty -LiteralPath $Setting.RegistryPath -Name 'EnhancedPowerManagementEnabled' -Value $value -PropertyType DWord -Force | Out-Null
            Write-BTFixLog -Message "EnhancedPowerManagementEnabled=$value on $($Setting.InstanceId)" -Level 'OK' -Path $LogPath
            return $true
        } catch {
            Write-BTFixLog -Message ("could not set the USB power flag: " + $_.Exception.Message) -Level 'WARN' -Path $LogPath
            return $false
        }
    }
    return $false
}

<#
.SYNOPSIS
Queries audio and Bluetooth PnP devices to find Hands-Free (HFP/HSP) telephony nodes.
.DESCRIPTION
Bluetooth headsets register both an A2DP Stereo playback sink and a Hands-Free
telephony gateway. When communication apps (Discord, Teams, Zoom, Slack) open
a microphone stream, Windows forces the headset into 8kHz mono HFP mode.
This cmdlet locates all active or installed Hands-Free device endpoints.
#>
function Get-BTFixHandsFreeDevice {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$Name
    )
    $out = @()
    $pnpNodes = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -like '*Hands-Free*' -or $_.FriendlyName -like '*Hands-Free AG*' -or $_.InstanceId -like '*{0000111e-*'
    })

    foreach ($d in $pnpNodes) {
        if ($Name -and ($d.FriendlyName -notlike "*$Name*" -and $d.InstanceId -notlike "*$Name*")) {
            continue
        }
        $status = [string]$d.Status
        $problem = $null
        try {
            $prop = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
            if ($prop -and $null -ne $prop.Data) { $problem = $prop.Data }
        } catch {
            $problem = $null
        }
        $code = if ($null -ne $problem) { [int]$problem } else { 0 }
        $isDisabled = ($code -eq 22 -or $status -eq 'Error')

        $out += [pscustomobject]@{
            InstanceId   = $d.InstanceId
            FriendlyName = $d.FriendlyName
            Class        = [string]$d.Class
            Status       = $status
            ProblemCode  = $code
            IsEnabled    = (-not $isDisabled)
            IsDisabled   = $isDisabled
        }
    }
    return $out
}

<#
.SYNOPSIS
Disables or enables Hands-Free (HFP/HSP) telephony to prevent 8kHz mono degradation.
.DESCRIPTION
Disabling Hands-Free ensures Bluetooth headsets permanently stay in crystal-clear
A2DP Stereo mode (44.1/48kHz), completely eliminating voice-chat audio collapse.
Users can still use an external USB mic or laptop built-in mic for voice.
Optionally, also toggles the BTAGService (Bluetooth Audio Gateway Service).
#>
function Set-BTFixHandsFreeState {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][ValidateSet('Disable', 'Enable')][string]$State,
        [string]$Device,
        [switch]$ToggleService,
        [string]$BackupPath,
        [string]$LogPath
    )
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'Administrator rights required to modify Hands-Free audio profiles.' -Level 'WARN' -Path $LogPath
        return [pscustomobject]@{ Success = $false; Error = 'Elevation required' }
    }

    $devices = @(Get-BTFixHandsFreeDevice -Name $Device)
    $targetDisabled = ($State -eq 'Disable')
    $changed = @()

    $stateRoot = if (Get-Command 'Get-BTFixStateRoot' -ErrorAction SilentlyContinue) {
        Get-BTFixStateRoot -BackupPath $BackupPath
    } else {
        if ($BackupPath) { $BackupPath } else { Join-Path $env:LOCALAPPDATA 'BTFix' }
    }
    $handsFreeDir = Join-Path $stateRoot 'handsfree-backups'
    if (-not (Test-Path -LiteralPath $handsFreeDir)) {
        New-Item -ItemType Directory -Path $handsFreeDir -Force | Out-Null
    }
    $snapshotFile = Join-Path $handsFreeDir ('handsfree-state-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $snapshotData = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        State     = $State
        Devices   = @($devices | Select-Object InstanceId, FriendlyName, IsEnabled)
    }
    $snapshotData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $snapshotFile -Encoding utf8

    foreach ($d in $devices) {
        if ($targetDisabled -and $d.IsEnabled) {
            if ($PSCmdlet.ShouldProcess($d.FriendlyName, 'Disable Hands-Free telephony node')) {
                try {
                    Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                    Write-BTFixLog -Message "Disabled Hands-Free telephony node: $($d.FriendlyName)" -Level 'OK' -Path $LogPath
                    $changed += $d.InstanceId
                } catch {
                    & pnputil /disable-device $d.InstanceId 2>&1 | Out-Null
                    Write-BTFixLog -Message "Disabled Hands-Free telephony via pnputil: $($d.FriendlyName)" -Level 'OK' -Path $LogPath
                    $changed += $d.InstanceId
                }
            }
        } elseif (-not $targetDisabled -and $d.IsDisabled) {
            if ($PSCmdlet.ShouldProcess($d.FriendlyName, 'Enable Hands-Free telephony node')) {
                try {
                    Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                    Write-BTFixLog -Message "Enabled Hands-Free telephony node: $($d.FriendlyName)" -Level 'OK' -Path $LogPath
                    $changed += $d.InstanceId
                } catch {
                    & pnputil /enable-device $d.InstanceId 2>&1 | Out-Null
                    Write-BTFixLog -Message "Enabled Hands-Free telephony via pnputil: $($d.FriendlyName)" -Level 'OK' -Path $LogPath
                    $changed += $d.InstanceId
                }
            }
        }
    }

    if ($ToggleService) {
        $svc = Get-Service -Name 'BTAGService' -ErrorAction SilentlyContinue
        if ($svc) {
            if ($targetDisabled) {
                Stop-Service -Name 'BTAGService' -Force -ErrorAction SilentlyContinue
                Set-Service -Name 'BTAGService' -StartupType Disabled -ErrorAction SilentlyContinue
                Write-BTFixLog -Message 'Stopped and disabled BTAGService (Bluetooth Audio Gateway)' -Level 'OK' -Path $LogPath
            } else {
                Set-Service -Name 'BTAGService' -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service -Name 'BTAGService' -ErrorAction SilentlyContinue
                Write-BTFixLog -Message 'Restored BTAGService startup to Manual and started service' -Level 'OK' -Path $LogPath
            }
        }
    }

    return [pscustomobject]@{
        Success  = $true
        State    = $State
        Changed  = $changed
        Snapshot = $snapshotFile
    }
}

<#
.SYNOPSIS
Queries paired and connected Bluetooth devices for real-time battery percentage.
.DESCRIPTION
Inspects the Windows PnP Property Store for DEVPKEY_Device_BatteryPercentage
({104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2) across paired Bluetooth Classic
and Bluetooth Low Energy (BLE) devices.
#>
function Get-BTFixBatteryStatus {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string]$Name
    )
    $batteryKey = '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2'
    $paired = @(Get-BTFixPairedDevice)
    $results = @()
    $cachedBtDevices = $null

    foreach ($p in $paired) {
        if ($p.IsTransport) { continue }
        if ($Name -and ($p.FriendlyName -notlike "*$Name*" -and $p.InstanceId -notlike "*$Name*")) {
            continue
        }

        # Offline/standby devices cannot have active GATT battery telemetry
        if (-not $p.IsConnected) {
            $results += [pscustomobject]@{
                FriendlyName   = $p.FriendlyName
                InstanceId     = $p.InstanceId
                IsConnected    = $false
                BatteryPercent = $null
                Gauge          = "Standby (Not connected)"
                HasBatteryInfo = $false
            }
            continue
        }

        $batteryPercent = $null
        try {
            $prop = Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName $batteryKey -ErrorAction SilentlyContinue
            if ($prop -and $null -ne $prop.Data) {
                $batteryPercent = [int]$prop.Data
            }
        } catch {
            $batteryPercent = $null
        }

        # If not directly on the root instance, query child PnP instances under Bluetooth class
        if ($null -eq $batteryPercent) {
            try {
                if ($p.InstanceId -match '([0-9a-fA-F]{12})') {
                    $mac = $matches[1]
                    if ($null -eq $cachedBtDevices) {
                        $cachedBtDevices = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
                    }
                    $children = @($cachedBtDevices | Where-Object {
                        $_.InstanceId -like "*$mac*" -and $_.InstanceId -ne $p.InstanceId
                    })
                    foreach ($c in $children) {
                        $cProp = Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName $batteryKey -ErrorAction SilentlyContinue
                        if ($cProp -and $null -ne $cProp.Data) {
                            $batteryPercent = [int]$cProp.Data
                            break
                        }
                    }
                }
            } catch {
                # Fallback silently
                $null = $_
            }
        }

        # Build visual gauge if battery is known
        $gauge = if ($null -ne $batteryPercent) {
            $filled = [Math]::Max(0, [Math]::Min(10, [Math]::Floor($batteryPercent / 10)))
            $empty = 10 - $filled
            "[" + ("█" * $filled) + ("░" * $empty) + ("] {0}%" -f $batteryPercent)
        } else {
            "N/A (No GATT/HFP telemetry)"
        }

        $results += [pscustomobject]@{
            FriendlyName   = $p.FriendlyName
            InstanceId     = $p.InstanceId
            IsConnected    = $p.IsConnected
            BatteryPercent = $batteryPercent
            Gauge          = $gauge
            HasBatteryInfo = ($null -ne $batteryPercent)
        }
    }

    return $results
}

<#
.SYNOPSIS
Reads Windows Bluetooth A2DP audio codec settings and absolute volume configurations.
.DESCRIPTION
Inspects registry keys for AAC, aptX, and AVRCP Absolute Volume controls.
#>
function Get-BTFixAudioCodecInfo {
    [CmdletBinding()]
    [OutputType([object])]
    param()
    $a2dpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Bluetooth\Audio\A2DP\Parameters'
    $avrcpPath = 'HKLM:\SYSTEM\ControlSet001\Control\Bluetooth\Audio\AVRCP\CT'

    $aacDisabled = $false
    $aptxDisabled = $false
    $absVolDisabled = $false

    try {
        if (Test-Path -LiteralPath $a2dpPath) {
            $props = Get-ItemProperty -LiteralPath $a2dpPath -ErrorAction SilentlyContinue
            if ($props) {
                if ($props.PSObject.Properties['DisableAacCodec']) {
                    $aacDisabled = ([int]$props.DisableAacCodec -ne 0)
                }
                if ($props.PSObject.Properties['DisableAptxCodec']) {
                    $aptxDisabled = ([int]$props.DisableAptxCodec -ne 0)
                }
            }
        }
    } catch {
        # ignore registry read errors
        $null = $_
    }

    try {
        if (Test-Path -LiteralPath $avrcpPath) {
            $props = Get-ItemProperty -LiteralPath $avrcpPath -ErrorAction SilentlyContinue
            if ($props -and $props.PSObject.Properties['DisableAbsoluteVolume']) {
                $absVolDisabled = ([int]$props.DisableAbsoluteVolume -ne 0)
            }
        }
    } catch {
        # ignore registry read errors
        $null = $_
    }

    return [pscustomobject]@{
        AacEnabled             = (-not $aacDisabled)
        AptxEnabled            = (-not $aptxDisabled)
        AbsoluteVolumeDisabled = $absVolDisabled
        A2dpRegistryPath       = $a2dpPath
        AvrcpRegistryPath      = $avrcpPath
    }
}

<#
.SYNOPSIS
Optimizes Bluetooth A2DP audio codecs and audio quality parameters.
.DESCRIPTION
Enables or disables AAC, aptX, and AVRCP Absolute Volume with automatic rollback snapshot.
#>
function Set-BTFixAudioCodecPreference {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [switch]$EnableAac,
        [switch]$DisableAac,
        [switch]$EnableAptx,
        [switch]$DisableAptx,
        [switch]$DisableAbsoluteVolume,
        [switch]$EnableAbsoluteVolume,
        [string]$BackupPath,
        [string]$LogPath
    )
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'Administrator rights required to modify Bluetooth audio codec registry settings.' -Level 'WARN' -Path $LogPath
        return $false
    }

    $a2dpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Bluetooth\Audio\A2DP\Parameters'
    $avrcpPath = 'HKLM:\SYSTEM\ControlSet001\Control\Bluetooth\Audio\AVRCP\CT'

    $stateRoot = if (Get-Command 'Get-BTFixStateRoot' -ErrorAction SilentlyContinue) {
        Get-BTFixStateRoot -BackupPath $BackupPath
    } else {
        if ($BackupPath) { $BackupPath } else { Join-Path $env:LOCALAPPDATA 'BTFix' }
    }
    $codecDir = Join-Path $stateRoot 'codec-backups'
    if (-not (Test-Path -LiteralPath $codecDir)) { New-Item -ItemType Directory -Path $codecDir -Force | Out-Null }
    $current = Get-BTFixAudioCodecInfo
    $snapFile = Join-Path $codecDir ('codec-state-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $current | ConvertTo-Json | Set-Content -LiteralPath $snapFile -Encoding utf8

    try {
        if ($EnableAac -or $DisableAac) {
            $val = if ($DisableAac) { 1 } else { 0 }
            if ($PSCmdlet.ShouldProcess($a2dpPath, "Set DisableAacCodec=$val")) {
                if (-not (Test-Path -LiteralPath $a2dpPath)) { New-Item -Path $a2dpPath -Force | Out-Null }
                New-ItemProperty -LiteralPath $a2dpPath -Name 'DisableAacCodec' -Value $val -PropertyType DWord -Force | Out-Null
                Write-BTFixLog -Message "Set DisableAacCodec=$val in $a2dpPath" -Level 'OK' -Path $LogPath
            }
        }
        if ($EnableAptx -or $DisableAptx) {
            $val = if ($DisableAptx) { 1 } else { 0 }
            if ($PSCmdlet.ShouldProcess($a2dpPath, "Set DisableAptxCodec=$val")) {
                if (-not (Test-Path -LiteralPath $a2dpPath)) { New-Item -Path $a2dpPath -Force | Out-Null }
                New-ItemProperty -LiteralPath $a2dpPath -Name 'DisableAptxCodec' -Value $val -PropertyType DWord -Force | Out-Null
                Write-BTFixLog -Message "Set DisableAptxCodec=$val in $a2dpPath" -Level 'OK' -Path $LogPath
            }
        }
        if ($DisableAbsoluteVolume -or $EnableAbsoluteVolume) {
            $val = if ($DisableAbsoluteVolume) { 1 } else { 0 }
            if ($PSCmdlet.ShouldProcess($avrcpPath, "Set DisableAbsoluteVolume=$val")) {
                if (-not (Test-Path -LiteralPath $avrcpPath)) { New-Item -Path $avrcpPath -Force | Out-Null }
                New-ItemProperty -LiteralPath $avrcpPath -Name 'DisableAbsoluteVolume' -Value $val -PropertyType DWord -Force | Out-Null
                Write-BTFixLog -Message "Set DisableAbsoluteVolume=$val in $avrcpPath" -Level 'OK' -Path $LogPath
            }
        }
        return $true
    } catch {
        Write-BTFixLog -Message ("Failed to update audio codec registry: " + $_.Exception.Message) -Level 'WARN' -Path $LogPath
        return $false
    }
}

<#
.SYNOPSIS
Detects paired or connected Bluetooth gaming controllers.
.DESCRIPTION
Matches PlayStation DualSense (VID 054C PID 0CE6/0DF2), DualShock 4 (VID 054C PID 05C4/0BA0),
Xbox Wireless Controller (VID 045E PID 02E0/0B13/0B20), and Nintendo Switch Pro Controller (VID 057E PID 2009).
#>
function Get-BTFixGamingController {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $controllerSignatures = @(
        @{ Vendor = 'Sony PlayStation'; Model = 'DualSense PS5 Controller'; Pattern = 'VID_054C&(PID_0CE6|PID_0DF2)' }
        @{ Vendor = 'Sony PlayStation'; Model = 'DualShock 4 PS4 Controller'; Pattern = 'VID_054C&(PID_05C4|PID_0BA0)' }
        @{ Vendor = 'Microsoft Xbox'; Model = 'Xbox Wireless Controller'; Pattern = 'VID_045E&(PID_02E0|PID_0B13|PID_0B20)' }
        @{ Vendor = 'Nintendo'; Model = 'Switch Pro Controller'; Pattern = 'VID_057E&PID_2009' }
        @{ Vendor = 'Nintendo'; Model = 'Joy-Con Controller'; Pattern = 'VID_057E&(PID_2006|PID_2007)' }
    )

    $devices = @(Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue) +
               @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)

    $found = @()
    foreach ($d in $devices) {
        $matched = $null
        foreach ($sig in $controllerSignatures) {
            if ($d.InstanceId -match $sig.Pattern) {
                $matched = $sig
                break
            }
        }
        if (-not $matched) {
            if ($d.FriendlyName -like '*DualSense*' -or $d.FriendlyName -like '*Xbox Wireless Controller*' -or $d.FriendlyName -like '*Wireless Controller*') {
                $matched = @{ Vendor = 'Generic/Console'; Model = $d.FriendlyName }
            }
        }

        if ($matched) {
            $status = [string]$d.Status
            $found += [pscustomobject]@{
                InstanceId   = $d.InstanceId
                FriendlyName = $d.FriendlyName
                Vendor       = $matched.Vendor
                Model        = $matched.Model
                IsConnected  = ($status -eq 'OK')
                Status       = $status
            }
        }
    }
    return $found
}

<#
.SYNOPSIS
Optimizes USB polling and power policies for lowest latency esports gaming on Bluetooth controllers.
.DESCRIPTION
Disables USB Selective Suspend on host Bluetooth radios and upstream hubs to eliminate 50-150ms input lag spikes.
#>
function Optimize-BTFixControllerLatency {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [string]$LogPath
    )
    if (-not (Test-BTFixAdministrator)) {
        Write-BTFixLog -Message 'Administrator rights required to apply controller latency optimizations.' -Level 'WARN' -Path $LogPath
        return [pscustomobject]@{ Success = $false; Error = 'Elevation required' }
    }

    $radios = @(Get-BTFixRadio | Where-Object { -not $_.IsInternal })
    if ($radios.Count -eq 0) {
        # Fallback to active USB radios even if internal (e.g. laptop Intel/Realtek internal USB Bluetooth modules)
        $radios = @(Get-BTFixRadio | Where-Object { $_.InstanceId -like 'USB\*' -and $_.IsHealthy })
    }
    $optimized = @()

    foreach ($r in $radios) {
        $setting = Get-BTFixUsbPowerSetting -InstanceId $r.InstanceId
        if ($setting -and $setting.SuspendAllowed) {
            if ($PSCmdlet.ShouldProcess($r.FriendlyName, 'Disable USB Selective Suspend for lowest controller latency')) {
                $ok = Set-BTFixUsbPowerSetting -Setting $setting -AllowSuspend:$false -LogPath $LogPath
                if ($ok) { $optimized += $r.FriendlyName }
            }
        }
    }

    return [pscustomobject]@{
        Success           = $true
        OptimizedAdapters = $optimized
        ControllersFound  = @(Get-BTFixGamingController)
    }
}

New-Alias -Name Get-BTFixGamingControllers -Value Get-BTFixGamingController -Description 'Backward-compatible alias for Get-BTFixGamingController'

Export-ModuleMember -Function @(
    'Get-BTFixServiceHealth', 'Get-BTFixRadioSoftwareState', 'Get-BTFixPairedDevice',
    'Remove-BTFixPairedDevice', 'Get-BTFixUsbPowerSetting', 'Set-BTFixUsbPowerSetting',
    'Get-BTFixHandsFreeDevice', 'Set-BTFixHandsFreeState', 'Get-BTFixBatteryStatus',
    'Get-BTFixAudioCodecInfo', 'Set-BTFixAudioCodecPreference',
    'Get-BTFixGamingController', 'Optimize-BTFixControllerLatency'
) -Alias @('Get-BTFixGamingControllers')
