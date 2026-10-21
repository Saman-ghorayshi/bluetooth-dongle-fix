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
        Family      = 'Intel AX211 / AX201 / AX210'
        Vendor      = 'Intel'
        DriverHint  = 'Install the Intel Bluetooth driver from the laptop OEM; Windows Update often carries an older one that fails with 0x80070426.'
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
        Pattern     = 'VID_0EAC&PID_&'
        Family      = 'MediaTek / Broadcom combo dongles'
        Vendor      = 'MediaTek'
        DriverHint  = 'MediaTek combo dongles usually need the vendor INF; a driver from another chipset can break the Wi-Fi half.'
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
