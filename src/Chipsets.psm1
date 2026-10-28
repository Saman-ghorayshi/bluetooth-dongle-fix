# Known Bluetooth chipset families and where to get a working driver.
#
# Windows ships a generic Bluetooth driver (bth.inf) that covers most chipsets.
# When a radio is broken *and* the generic driver cannot start it, the chipset
# usually needs a vendor driver. This table maps USB vendor/product ids to the
# family, the vendor and the place to get a driver.
#
# The table is data only - BTFix never downloads anything on its own.

Set-StrictMode -Version Latest

$script:ChipsetTable = @(
    [pscustomobject]@{
        Pattern     = 'VID_0A12&PID_0001'
        Family      = 'CSR / Cambridge Silicon Radio (CSR8510 A10 class)'
        Vendor      = 'Cambridge Silicon Radio / countless rebadges'
        DriverHint  = 'The Windows generic driver is normally sufficient. If the radio still fails with Code 31, it is a dual-radio conflict, not a driver problem.'
        DriverUrl   = ''
    },
    [pscustomobject]@{
        Pattern     = 'VID_0BDA&PID_8771'
        Family      = 'Realtek RTL8761B USB 5.0 (TP-Link UB500, UGREEN, Baseus)'
        Vendor      = 'Realtek'
        DriverHint  = 'Realtek Bluetooth 5.0 adapter. Windows generic driver works, or install the Realtek/TP-Link vendor driver.'
        DriverUrl   = 'https://www.tp-link.com/support/download/ub500/'
    },
    [pscustomobject]@{
        Pattern     = 'VID_10D7&PID_B012'
        Family      = 'Actions Semiconductor ATS2851 USB 5.3'
        Vendor      = 'Actions'
        DriverHint  = 'Generic Windows Bluetooth driver handles basic audio; install vendor driver if LE audio is unstable.'
        DriverUrl   = ''
    },
    [pscustomobject]@{
        Pattern     = 'VID_0BDA&PID_4853'
        Family      = 'Realtek RTL8852BE / RTL8761B'
        Vendor      = 'Realtek'
        DriverHint  = 'Use the laptop OEM driver (Intel/Realtek Wireless Bluetooth). The Windows generic driver works but misses the vendor power management.'
        DriverUrl   = 'https://www.intel.com/content/www/us/en/support/detect.html'
    },
    [pscustomobject]@{
        Pattern     = 'VID_0BDA&PID_B00B'
        Family      = 'Realtek RTL8723B / RTL8761B'
        Vendor      = 'Realtek'
        DriverHint  = 'OEM driver preferred; generic driver usually works.'
        DriverUrl   = 'https://www.intel.com/content/www/us/en/support/detect.html'
    },
    [pscustomobject]@{
        Pattern     = 'VID_8087&'
        Family      = 'Intel Wireless Bluetooth (AX200 / AX201 / AX210 / AX211 / BE200)'
        Vendor      = 'Intel'
        DriverHint  = 'Intel Wireless Bluetooth. If device crashes with Code 10/43 after sleep, disable USB Selective Suspend in Device Manager.'
        DriverUrl   = 'https://www.intel.com/content/www/us/en/support/detect.html'
    },
    [pscustomobject]@{
        Pattern     = 'VID_0CF3&'
        Family      = 'Qualcomm Atheros (QCA9377, AR9462)'
        Vendor      = 'Qualcomm / Atheros'
        DriverHint  = 'The generic driver is fine on Windows 10/11. On Windows 7 install the Atheros Bluetooth driver.'
        DriverUrl   = 'https://www.atheros.com'
    },
    [pscustomobject]@{
        Pattern     = 'VID_0E8D&'
        Family      = 'MediaTek MT7921 / MT7922 Wi-Fi 6/6E Bluetooth'
        Vendor      = 'MediaTek'
        DriverHint  = 'MediaTek combo card (common on AMD Ryzen laptops). Use OEM driver; if Bluetooth disappears after sleep, disable Fast Startup.'
        DriverUrl   = 'https://www.mediatek.com'
    },
    [pscustomobject]@{
        Pattern     = 'VID_1D6B'
        Family      = 'Linux Foundation USB (not a radio)'
        Vendor      = 'n/a'
        DriverHint  = 'This is a virtual device, not a Bluetooth radio.'
        DriverUrl   = ''
    },
    [pscustomobject]@{
        Pattern     = 'VID_0A5C&PID_'
        Family      = 'Broadcom (BCM2045 / BCM2070 boards)'
        Vendor      = 'Broadcom / HP'
        DriverHint  = 'Use the OEM driver shipped with the dongle.'
        DriverUrl   = ''
    },
    [pscustomobject]@{
        Pattern     = 'VID_33FA&'
        Family      = 'Barrot BR8651 / BR8041 USB 5.3'
        Vendor      = 'Barrot Technology'
        DriverHint  = 'Standard in-box Microsoft driver works on Windows 11. If Code 31 appears, park competing internal radio.'
        DriverUrl   = ''
    },
    [pscustomobject]@{
        Pattern     = 'VID_05AC&'
        Family      = 'Apple Broadcom Bluetooth Host Controller'
        Vendor      = 'Apple / Broadcom'
        DriverHint  = 'Boot Camp Windows Apple Bluetooth controller. Use Apple Boot Camp support software drivers.'
        DriverUrl   = 'https://support.apple.com/boot-camp'
    }
)

<#
.SYNOPSIS
Returns the chipset guidance rows that match a hardware id.
#>
function Get-BTFixChipset {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$HardwareId)

    $ids = @()
    if ($HardwareId) {
        $ids = @($HardwareId -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($ids.Count -eq 0) { return $script:ChipsetTable }

    $found = @()
    foreach ($row in $script:ChipsetTable) {
        foreach ($id in $ids) {
            if ($id -like ('*' + $row.Pattern + '*')) {
                $found += $row
                break
            }
        }
    }
    if ($found.Count -eq 0) {
        return @([pscustomobject]@{
            Pattern     = ($ids -join ' ')
            Family      = 'Unknown chipset'
            Vendor      = 'unknown'
            DriverHint  = 'No guidance for this id yet. The Windows generic driver is normally the right one; open an issue with the id and the report from -Mode Report.'
            DriverUrl   = ''
        })
    }
    return $found
}

<#
.SYNOPSIS
Returns every known chipset row (for the -ListChipsets output).
#>
function Get-BTFixChipsetTable {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return $script:ChipsetTable
}

Export-ModuleMember -Function @('Get-BTFixChipset', 'Get-BTFixChipsetTable')
