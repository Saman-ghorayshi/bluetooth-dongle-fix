# Superiority Evaluation Engine: Automatically detects and ranks multiple Bluetooth
# radios on Windows to identify the superior hardware based on Bluetooth specification (LMP),
# antenna placement, and hardware reliability.

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Health.psm1')

<#
.SYNOPSIS
Maps numeric Link Manager Protocol (LMP) versions to official Bluetooth specifications.
#>
function Get-BTFixLmpVersionName {
    [CmdletBinding()]
    [OutputType([string])]
    param([int]$LmpVersion)

    switch ($LmpVersion) {
        0  { 'Bluetooth 1.0b' }
        1  { 'Bluetooth 1.1' }
        2  { 'Bluetooth 1.2' }
        3  { 'Bluetooth 2.0 + EDR' }
        4  { 'Bluetooth 2.1 + EDR' }
        5  { 'Bluetooth 3.0 + HS' }
        6  { 'Bluetooth 4.0' }
        7  { 'Bluetooth 4.1' }
        8  { 'Bluetooth 4.2' }
        9  { 'Bluetooth 5.0' }
        10 { 'Bluetooth 5.1' }
        11 { 'Bluetooth 5.2' }
        12 { 'Bluetooth 5.3' }
        13 { 'Bluetooth 5.4' }
        14 { 'Bluetooth 6.0' }
        default {
            if ($LmpVersion -gt 14) { "Bluetooth (LMP $LmpVersion)" }
            else { 'Unknown' }
        }
    }
}

<#
.SYNOPSIS
Queries detailed Bluetooth radio hardware specifications from PnP properties.
#>
function Get-BTFixRadioSpecs {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$InstanceId)

    $lmp = $null
    $hci = $null
    $lmpSub = $null
    $hciSub = $null

    try {
        $props = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue
        if ($props) {
            $lmpProp = $props | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioLmpVersion' -or $_.Key -like '*{A92F26CA-EDA7-4B1D-9DB2-27B68AA5A2EB} 4*' } | Select-Object -First 1
            if ($lmpProp -and $null -ne $lmpProp.Data) { $lmp = [int]$lmpProp.Data }

            $hciProp = $props | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioHciVersion' -or $_.Key -like '*{A92F26CA-EDA7-4B1D-9DB2-27B68AA5A2EB} 6*' } | Select-Object -First 1
            if ($hciProp -and $null -ne $hciProp.Data) { $hci = [int]$hciProp.Data }

            $lmpSubProp = $props | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioLmpSubversion' -or $_.Key -like '*{A92F26CA-EDA7-4B1D-9DB2-27B68AA5A2EB} 5*' } | Select-Object -First 1
            if ($lmpSubProp -and $null -ne $lmpSubProp.Data) { $lmpSub = [int]$lmpSubProp.Data }

            $hciSubProp = $props | Where-Object { $_.KeyName -eq 'DEVPKEY_Bluetooth_RadioHciRevision' -or $_.Key -like '*{A92F26CA-EDA7-4B1D-9DB2-27B68AA5A2EB} 7*' } | Select-Object -First 1
            if ($hciSubProp -and $null -ne $hciSubProp.Data) { $hciSub = [int]$hciSubProp.Data }
        }
    } catch {
        Write-Verbose "Could not query Bluetooth PnP properties for $InstanceId"
    }

    $versionName = if ($null -ne $lmp) { Get-BTFixLmpVersionName -LmpVersion $lmp } else { 'Unknown' }

    return [pscustomobject]@{
        InstanceId       = $InstanceId
        LmpVersion       = $lmp
        LmpSubversion    = $lmpSub
        HciVersion       = $hci
        HciRevision      = $hciSub
        BluetoothVersion = $versionName
    }
}

<#
.SYNOPSIS
Calculates an objective capability and RF superiority score for a Bluetooth radio (0-100).
.DESCRIPTION
Evaluation criteria:
1. Bluetooth Specification (LMP version): Modern specs (5.0+) provide LE 2M, Coded PHY long range, and LC3 LE Audio.
2. Form Factor / Antenna Placement: External USB dongles avoid laptop chassis metal shielding and Wi-Fi 2.4GHz coexistence antenna time-slicing.
3. Driver Modernity: Up-to-date drivers ensure stability on Windows 11.
#>
function Get-BTFixRadioScore {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][object]$Radio,
        [object]$Specs
    )

    $score = 0
    $factors = @()

    $lmp = if ($Specs -and $null -ne $Specs.LmpVersion) {
        $Specs.LmpVersion
    } elseif ($Radio.PSObject.Properties['LmpVersion'] -and $null -ne $Radio.LmpVersion) {
        $Radio.LmpVersion
    } else {
        $null
    }

    # Criterion 1: Bluetooth Specification (up to 55 points)
    if ($null -ne $lmp) {
        if ($lmp -ge 13) {
            $score += 55
            $factors += "Bluetooth 5.4+ (Next-gen LE Audio & Periodic Sync)"
        } elseif ($lmp -eq 12) {
            $score += 53
            $factors += "Bluetooth 5.3 (Connection Subrating & Channel Classification)"
        } elseif ($lmp -eq 11) {
            $score += 50
            $factors += "Bluetooth 5.2 (LE Audio Isochronous Channels & EATT)"
        } elseif ($lmp -eq 10) {
            $score += 48
            $factors += "Bluetooth 5.1 (Direction Finding & Faster Advertising)"
        } elseif ($lmp -eq 9) {
            $score += 45
            $factors += "Bluetooth 5.0 (2 Mbps High Speed & 4x Extended Range)"
        } elseif ($lmp -eq 8) {
            $score += 35
            $factors += "Bluetooth 4.2 (Secure Connections & Data Packet Length Extension)"
        } elseif ($lmp -eq 6) {
            $score += 25
            $factors += "Bluetooth 4.0 (Legacy Smart Ready)"
        } else {
            $score += [Math]::Min(30, ($lmp * 3))
            $factors += "Bluetooth LMP $lmp"
        }
    } else {
        $score += 30
        $factors += "Bluetooth Version Unspecified (Default Baseline)"
    }

    # Criterion 2: Antenna Environment & Form Factor (up to 30 points)
    if (-not $Radio.IsInternal) {
        $score += 30
        $factors += "External USB Dongle (Dedicated antenna, free from laptop chassis RF shielding and Wi-Fi combo interference)"
    } else {
        $isMobile = $true
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($cs -and $null -ne $cs.PCSystemType) {
                $isMobile = ($cs.PCSystemType -in @(2, 8))
            }
        } catch {
            $isMobile = $true
        }
        if (-not $isMobile -and $lmp -and $lmp -ge 11) {
            $score += 28
            $factors += "Internal PCIe Card (Desktop chassis with dedicated RF clearance)"
        } else {
            $score += 15
            $factors += "Internal Adapter (Integrated, shares 2.4GHz antenna with Wi-Fi module)"
        }
    }

    # Criterion 3: Hardware Health (up to 15 points)
    if ($Radio.IsHealthy) {
        $score += 15
        $factors += "Radio is currently active and healthy"
    } elseif ($Radio.IsDisabled) {
        $score += 10
        $factors += "Radio is healthy but currently parked"
    } elseif ($Radio.ProblemCode -eq 31) {
        $score += 10
        $factors += "Radio is temporarily blocked by single-radio conflict (Code 31)"
    } elseif ($Radio.ProblemCode -in @(28, 43, 48, 10)) {
        # Severe driver or hardware failure (Code 48=blocked, 28=no driver, 43/10=cannot start)
        $score -= 40
        $factors += "Radio reported critical error code $($Radio.ProblemCode) (Driver missing, blocked, or device cannot start)"
    } else {
        $factors += "Radio reported problem code $($Radio.ProblemCode)"
    }

    return [pscustomobject]@{
        Radio            = $Radio
        Score            = $score
        Factors          = $factors
        BluetoothVersion = if ($Specs) { $Specs.BluetoothVersion } else { 'Unknown' }
    }
}

<#
.SYNOPSIS
Compares all detected radios and selects the superior adapter.
#>
function Get-BTFixSuperiorRadio {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][object[]]$Radios)

    if ($Radios.Count -eq 0) { return $null }
    if ($Radios.Count -eq 1) {
        $specs = Get-BTFixRadioSpecs -InstanceId $Radios[0].InstanceId
        $eval = Get-BTFixRadioScore -Radio $Radios[0] -Specs $specs
        return [pscustomobject]@{
            SuperiorRadio = $Radios[0]
            Scores        = @($eval)
            Reason        = "Only one Bluetooth radio ($($Radios[0].FriendlyName)) is present on this machine."
        }
    }

    $scored = @()
    foreach ($r in $Radios) {
        $specs = Get-BTFixRadioSpecs -InstanceId $r.InstanceId
        $eval = Get-BTFixRadioScore -Radio $r -Specs $specs
        $scored += $eval
    }

    $sorted = $scored | Sort-Object -Property Score -Descending
    $winner = $sorted[0]
    $runnerUp = $sorted[1]

    $reason = if ($winner.Score -gt $runnerUp.Score) {
        "'$($winner.Radio.FriendlyName)' scored $($winner.Score) pts vs '$($runnerUp.Radio.FriendlyName)' ($($runnerUp.Score) pts). Selected for: " + ($winner.Factors -join '; ')
    } else {
        "'$($winner.Radio.FriendlyName)' and '$($runnerUp.Radio.FriendlyName)' scored equally ($($winner.Score) pts). Preferred external dongle for dedicated RF antenna clearance."
    }

    return [pscustomobject]@{
        SuperiorRadio = $winner.Radio
        WinnerScore   = $winner
        RunnerUpScore = $runnerUp
        Scores        = $sorted
        Reason        = $reason
    }
}

Export-ModuleMember -Function @(
    'Get-BTFixLmpVersionName', 'Get-BTFixRadioSpecs', 'Get-BTFixRadioScore', 'Get-BTFixSuperiorRadio'
)
