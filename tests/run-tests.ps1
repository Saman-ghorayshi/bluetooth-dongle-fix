# BTFix test suite.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
#
# Everything is mocked: the suite never touches the real Bluetooth stack.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'TestFramework.ps1')
$src = Join-Path (Split-Path -Parent $here) 'src'
Import-Module (Join-Path $src 'BTFix.psm1') -Force
Import-Module (Join-Path $src 'ProblemCodes.psm1') -Force
Import-Module (Join-Path $src 'Chipsets.psm1') -Force
Import-Module (Join-Path $src 'Health.psm1') -Force
Import-Module (Join-Path $src 'Findings.psm1') -Force
Import-Module (Join-Path $src 'Superiority.psm1') -Force

function Get-TestRadio {
    param(
        [string]$Id,
        [string]$Name = 'Radio',
        [int]$Code = 0,
        [string]$Status = 'OK',
        [bool]$Internal = $false,
        [int]$Lmp = 0
    )
    return [pscustomobject]@{
        InstanceId     = $Id
        FriendlyName   = $Name
        Status         = $Status
        ProblemCode    = $Code
        ProblemStatus  = $null
        DriverVersion  = '10.0.26100.9711'
        DriverProvider = 'Microsoft'
        HardwareIds    = @('USB\VID_0A12&PID_0001')
        LocationInfo   = 'Port_#0001.Hub_#0001'
        Parent         = 'USB\ROOT_HUB30\4&84aac64&0&0'
        IsInternal     = $Internal
        IsHealthy      = ($Status -eq 'OK' -and $Code -eq 0)
        IsDisabled     = ($Code -eq 22)
        LmpVersion     = if ($Lmp -gt 0) { $Lmp } else { $null }
    }
}

# A radio exactly as Get-BTFixRadio returns it on a live machine: NO
# LmpVersion property at all, because that data only exists once a radio
# has successfully started. Mocks that attach it hide real selection bugs.
function Get-LiveShapeRadio {
    param(
        [string]$Id,
        [string]$Name = 'Radio',
        [int]$Code = 0,
        [string]$Status = 'OK',
        [bool]$Internal = $false
    )
    return [pscustomobject]@{
        InstanceId     = $Id
        FriendlyName   = $Name
        Status         = $Status
        ProblemCode    = $Code
        ProblemStatus  = $null
        DriverVersion  = '1.0.0.0'
        DriverProvider = $null
        HardwareIds    = @('USB\VID_0A12&PID_0001')
        LocationInfo   = 'Port_#0001.Hub_#0001'
        Parent         = 'USB\ROOT_HUB30\4&84aac64&0&0'
        IsInternal     = $Internal
        IsHealthy      = ($Status -eq 'OK' -and $Code -eq 0)
        IsDisabled     = ($Code -eq 22)
    }
}

Describe 'diagnosis' {
    It 'reports Healthy when a single radio works' {
        $d = Get-BTFixDiagnosis -Inventory @((Get-TestRadio -Id 'USB\A'))
        Assert-Equal 'Healthy' $d.Classification
        Assert-Equal 1 $d.Healthy.Count
        Assert-Equal 0 $d.Broken.Count
    }

    It 'reports a conflict when one radio is Code 31 and another is fine' {
        $d = Get-BTFixDiagnosis -Inventory @(
            (Get-TestRadio -Id 'USB\BAD' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error'),
            (Get-TestRadio -Id 'USB\GOOD' -Name 'Realtek Bluetooth Adapter')
        )
        Assert-Equal 'RadioConflictOrDriverStartFailure' $d.Classification
        Assert-Equal 'High' $d.Confidence
        Assert-True ($d.RecommendedActions -join ' ' -match 'Disable the other radio')
    }

    It 'treats problem code 22 as disabled, not broken' {
        $d = Get-BTFixDiagnosis -Inventory @(
            (Get-TestRadio -Id 'USB\OFF' -Name 'Realtek Bluetooth Adapter' -Code 22 -Status 'Error'),
            (Get-TestRadio -Id 'USB\ON' -Name 'Generic Bluetooth Radio')
        )
        Assert-Equal 'HealthyWithDisabledRadio' $d.Classification
        Assert-Equal 0 $d.Broken.Count
        Assert-Equal 1 $d.Disabled.Count
    }

    It 'reports when every radio is disabled' {
        $d = Get-BTFixDiagnosis -Inventory @(
            (Get-TestRadio -Id 'USB\OFF' -Code 22 -Status 'Error')
        )
        Assert-Equal 'AllRadiosDisabled' $d.Classification
        Assert-True ($d.RecommendedActions -join ' ' -match 'Re-enable')
    }

    It 'classifies a missing driver (code 28)' {
        $d = Get-BTFixDiagnosis -Inventory @(
            (Get-TestRadio -Id 'USB\NOdrv' -Code 28 -Status 'Error')
        )
        Assert-Equal 'DriverNotInstalled' $d.Classification
    }

    It 'classifies code 10 as cannot start' {
        $d = Get-BTFixDiagnosis -Inventory @(
            (Get-TestRadio -Id 'USB\X' -Code 10 -Status 'Error')
        )
        Assert-Equal 'DeviceCannotStart' $d.Classification
    }

    It 'reports when no radio exists at all' {
        $d = Get-BTFixDiagnosis -Inventory @() -NoLive
        Assert-Equal 'NoBluetoothRadio' $d.Classification
    }
}

Describe 'backups' {
    It 'writes a snapshot that lists every radio' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        try {
            $radios = @(
                (Get-TestRadio -Id 'USB\A' -Name 'Realtek Bluetooth Adapter' -Code 22 -Status 'Error'),
                (Get-TestRadio -Id 'USB\B' -Name 'Generic Bluetooth Radio')
            )
            $file = New-BTFixBackup -Radios $radios -BackupPath $dir
            Assert-True (Test-Path -LiteralPath $file)
            $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            Assert-Equal 2 $data.Radios.Count
            Assert-True ($data.Radios.InstanceId -contains 'USB\A')
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'finds the most recent snapshot again' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-BTFixBackup -Radios @((Get-TestRadio -Id 'USB\A')) -BackupPath $dir
            Start-Sleep -Seconds 1
            $null = New-BTFixBackup -Radios @((Get-TestRadio -Id 'USB\B')) -BackupPath $dir
            $latest = Get-BTFixLatestBackup -BackupPath $dir
            Assert-True ($null -ne $latest)
            Assert-True ($latest.Radios.InstanceId -contains 'USB\B')
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns nothing when no snapshot exists' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'backups') -Force | Out-Null
        try {
            Assert-True ($null -eq (Get-BTFixLatestBackup -BackupPath $dir))
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'snapshots the usb power state of external radios for rollback' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        try {
            $radios = @(
                (Get-LiveShapeRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Internal $false),
                (Get-LiveShapeRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Internal $true)
            )
            $file = New-BTFixBackup -Radios $radios -BackupPath $dir
            $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            Assert-True ($null -ne $data.UsbPowerSettings) 'expected UsbPowerSettings in the snapshot payload'
            Assert-Equal 1 @($data.UsbPowerSettings).Count 'only external radios should be snapshotted'
            Assert-Equal 'USB\DONGLE' $data.UsbPowerSettings[0].InstanceId
            Assert-True ($data.UsbPowerSettings[0].RegistryPath -like '*USB\DONGLE\Device Parameters')
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'report' {
    It 'renders a markdown report with a radio table' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        try {
            $file = Join-Path $dir 'report.md'
            $text = Write-BTFixReport -OutputPath $file
            Assert-True (Test-Path -LiteralPath $file)
            Assert-Match '## Radios' $text
            Assert-Match '## Recommended actions' $text
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'renders a machine-readable JSON twin' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-test-' + [guid]::NewGuid().ToString('N'))
        try {
            $file = Join-Path $dir 'report.json'
            $null = Write-BTFixReportJson -OutputPath $file
            Assert-True (Test-Path -LiteralPath $file)
            $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            Assert-Equal 'BTFix' $data.tool
            Assert-True ($null -ne $data.classification)
            Assert-True ($data.services.Count -ge 1)
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'tooling' {
    It 'exposes the public functions' {
        $exported = (Get-Module BTFix).ExportedFunctions.Keys
        foreach ($fn in @('Get-BTFixRadio', 'Get-BTFixDiagnosis', 'Invoke-BTFixRepair', 'Invoke-BTFixRollback', 'Write-BTFixReport', 'Resolve-BTFixWantedRadio')) {
            Assert-True ($exported -contains $fn) "expected $fn to be exported"
        }
    }

    It 'knows whether it is elevated' {
        $isAdmin = Test-BTFixAdministrator
        Assert-True ($isAdmin -is [bool])
    }

    It 'puts state under LOCALAPPDATA by default' {
        Assert-Match 'BTFix' (Get-BTFixStateRoot)
    }
}

Describe 'problem codes' {
    It 'maps code 31 to CM_PROB_FAILED_ADD' {
        $row = Get-BTFixProblemCode -Code 31
        Assert-Equal 'CM_PROB_FAILED_ADD' $row.Name
        Assert-True ($row.Fix -match 'radio')
    }

    It 'maps code 45 to CM_PROB_PHANTOM (not connected)' {
        Assert-Equal 'CM_PROB_PHANTOM' (Get-BTFixProblemCode -Code 45).Name
    }

    It 'knows the code Windows blocks drivers with' {
        Assert-Equal 'CM_PROB_DRIVER_BLOCKED' (Get-BTFixProblemCode -Code 48).Name
    }

    It 'returns nothing for an unknown code' {
        Assert-True ($null -eq (Get-BTFixProblemCode -Code 999))
    }

    It 'exposes the whole table' {
        $table = Get-BTFixProblemCodeTable
        Assert-True ($table.Count -ge 20) "expected at least 20 codes, got $($table.Count)"
    }
}

Describe 'chipset guidance' {
    It 'recognises the CSR style id' {
        $m = Get-BTFixChipset -HardwareId 'USB\VID_0A12&PID_0001&REV_8891'
        Assert-True (@($m)[0].Family -match 'CSR')
    }

    It 'recognises Intel, Realtek, and MediaTek ids' {
        Assert-True (@(Get-BTFixChipset -HardwareId 'USB\VID_8087&PID_0032')[0].Family -match 'Intel')
        Assert-True (@(Get-BTFixChipset -HardwareId 'USB\VID_0BDA&PID_4853')[0].Family -match 'Realtek')
        Assert-True (@(Get-BTFixChipset -HardwareId 'USB\VID_0E8D&PID_7961')[0].Family -match 'MediaTek')
    }

    It 'says so when it does not know the chipset' {
        $m = @(Get-BTFixChipset -HardwareId 'USB\VID_FFFF&PID_FFFF')
        Assert-Equal 'Unknown chipset' $m[0].Family
    }
}

Describe 'health checks' {
    It 'reports the services the stack needs' {
        $services = Get-BTFixServiceHealth
        Assert-Equal 5 $services.Count
        Assert-Equal 1 @($services | Where-Object { $_.Name -eq 'bthserv' }).Count
        Assert-Equal 1 @($services | Where-Object { $_.Name -eq 'AudioEndpointBuilder' }).Count
        Assert-Equal 1 @($services | Where-Object { $_.Name -eq 'BTAGService' }).Count
    }

    It 'can read the software radio switch' {
        $state = Get-BTFixRadioSoftwareState
        Assert-True ($state -is [object])
        Assert-True ($state.IsRadioOff -is [bool])
    }

    It 'lists paired peripherals without throwing' {
        $paired = @(Get-BTFixPairedDevice)
        Assert-True ($null -ne $paired)
    }

    It 'builds the usb power path from the device itself, not its parent hub' {
        # EnhancedPowerManagementEnabled lives under the radio's own Enum key
        # (Microsoft KB 2900614), not under the parent hub the old code used.
        $radios = @(Get-BTFixRadio | Where-Object { -not $_.IsInternal })
        if ($radios.Count -eq 0) { return }
        foreach ($r in $radios) {
            $p = Get-BTFixUsbPowerSetting -InstanceId $r.InstanceId
            Assert-True ($null -ne $p) 'expected a power-setting object'
            Assert-True ($p.RegistryPath -like "*\$($r.InstanceId)\Device Parameters") "unexpected path: $($p.RegistryPath)"
            Assert-True ($p.SuspendAllowed -is [bool])
        }
    }
}

Describe 'findings' {
    It 'flags the dual-radio conflict as auto-fixable' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\BAD' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error' -Internal $false),
                (Get-TestRadio -Id 'USB\GOOD' -Name 'Realtek Bluetooth Adapter' -Internal $true)
            ) -NoLive)
        $conflict = @($f | Where-Object { $_.Id -eq 'radio-31' })[0]
        Assert-True ($null -ne $conflict) 'expected a radio-31 finding'
        Assert-True $conflict.AutoFixable
        Assert-True ($conflict.Title -match 'fighting')
    }

    It 'flags dual-radio conflict as auto-fixable even when internal radio is listed first in enumeration' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\GOOD' -Name 'Realtek Bluetooth Adapter' -Internal $true),
                (Get-TestRadio -Id 'USB\BAD' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error' -Internal $false)
            ) -NoLive)
        $conflict = @($f | Where-Object { $_.Id -eq 'radio-31' })[0]
        Assert-True ($null -ne $conflict) 'expected a radio-31 finding regardless of enumeration order'
        Assert-True $conflict.AutoFixable
    }

    It 'flags dual-radio conflict as auto-fixable even if internal detection is ambiguous (order-independent)' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\GOOD' -Name 'Radio A' -Internal $false),
                (Get-TestRadio -Id 'USB\BAD' -Name 'Radio B' -Code 31 -Status 'Error' -Internal $false)
            ) -NoLive)
        $conflict = @($f | Where-Object { $_.Id -eq 'radio-31' })[0]
        Assert-True ($null -ne $conflict) 'expected a radio-31 finding even when both have IsInternal=false and good is listed first'
        Assert-True $conflict.AutoFixable
    }

    It 'honors -PreferInternal when breaking conflict' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Internal $false),
                (Get-TestRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Code 31 -Status 'Error' -Internal $true)
            ) -PreferInternal -NoLive)
        $conflict = @($f | Where-Object { $_.Id -eq 'radio-31' })[0]
        Assert-True ($null -ne $conflict)
        Assert-True $conflict.AutoFixable
    }

    It 'explains a missing driver' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\NOdrv' -Name 'Generic Bluetooth Radio' -Code 28 -Status 'Error')
            ) -NoLive)
        $row = @($f | Where-Object { $_.Id -eq 'radio-28' })[0]
        Assert-True ($null -ne $row)
        Assert-True ($row.Fix -match 'driver')
    }

    It 'warns that a blocked driver needs a vendor update' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\BLOCKED' -Code 48 -Status 'Error')
            ) -NoLive)
        $row = @($f | Where-Object { $_.Id -eq 'radio-48' })[0]
        Assert-True ($null -ne $row)
        Assert-True ($row.Title -match 'Driver Protection')
    }

    It 'flags when preferred dongle is disabled while internal radio is active' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Code 22 -Status 'Error' -Internal $false),
                (Get-TestRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Code 0 -Status 'OK' -Internal $true)
            ) -NoLive)
        $row = @($f | Where-Object { $_.Id -eq 'radio-conflict-disabled' })[0]
        Assert-True ($null -ne $row) 'expected radio-conflict-disabled finding'
        Assert-True $row.AutoFixable
        Assert-Equal 'High' $row.Severity
    }

    It 'reports no radio at all' {
        $f = @(Get-BTFixFinding -Inventory @() -NoLive)
        Assert-Equal 1 @($f | Where-Object { $_.Id -eq 'no-radio' }).Count
    }

    It 'detects when only one radio exists and it was left disabled' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\SOLO_DISABLED' -Name 'Realtek Bluetooth Adapter' -Code 22 -Status 'Error' -Internal $true)
            ) -NoLive)
        $row = @($f | Where-Object { $_.Id -eq 'single-radio-disabled' })[0]
        Assert-True ($null -ne $row) 'expected single-radio-disabled finding'
        Assert-True $row.AutoFixable
        Assert-Equal 'High' $row.Severity
    }
}

Describe 'repair wanted-radio selection' {
    It 'picks the code-31 dongle over the healthy internal radio (real radio shape)' {
        $dongle = Get-LiveShapeRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error' -Internal $false
        $internal = Get-LiveShapeRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Internal $true
        $w = Resolve-BTFixWantedRadio -Radios @($internal, $dongle)
        Assert-Equal 'USB\DONGLE' $w.InstanceId
    }

    It 'picks the code-31 dongle regardless of enumeration order' {
        $dongle = Get-LiveShapeRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error' -Internal $false
        $internal = Get-LiveShapeRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Internal $true
        $w = Resolve-BTFixWantedRadio -Radios @($dongle, $internal)
        Assert-Equal 'USB\DONGLE' $w.InstanceId
    }

    It 'honors -PreferInternal even when a dongle is conflict-blocked' {
        $dongle = Get-LiveShapeRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error' -Internal $false
        $internal = Get-LiveShapeRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Internal $true
        $w = Resolve-BTFixWantedRadio -Radios @($dongle, $internal) -PreferInternal
        Assert-Equal 'USB\INTERNAL' $w.InstanceId
    }

    It 'honors an explicit -Radio over every other rule' {
        $dongle = Get-LiveShapeRadio -Id 'USB\DONGLE' -Code 31 -Status 'Error' -Internal $false
        $internal = Get-LiveShapeRadio -Id 'USB\INTERNAL' -Internal $true
        $w = Resolve-BTFixWantedRadio -Radios @($dongle, $internal) -Radio 'USB\INTERNAL'
        Assert-Equal 'USB\INTERNAL' $w.InstanceId
    }

    It 'keeps a healthy internal over a dongle with a real driver fault (code 48)' {
        $dongle = Get-LiveShapeRadio -Id 'USB\BLOCKED' -Name 'Broken Dongle' -Code 48 -Status 'Error' -Internal $false
        $internal = Get-LiveShapeRadio -Id 'USB\INTERNAL' -Name 'Working Internal' -Internal $true
        $w = Resolve-BTFixWantedRadio -Radios @($dongle, $internal)
        Assert-Equal 'USB\INTERNAL' $w.InstanceId
    }

    It 'uses real capability data when both radios are benchmarkable' {
        $dongle = Get-TestRadio -Id 'USB\OLD' -Name 'Legacy Dongle' -Internal $false -Lmp 4
        $internal = Get-TestRadio -Id 'USB\NEW' -Name 'Modern Internal' -Internal $true -Lmp 12
        $w = Resolve-BTFixWantedRadio -Radios @($dongle, $internal)
        Assert-Equal 'USB\NEW' $w.InstanceId
    }

    It 'returns nothing for an empty inventory' {
        Assert-True ($null -eq (Resolve-BTFixWantedRadio -Radios @()))
    }
}

Describe 'instance-id classification' {
    It 'rejects peripheral and protocol enumerators' {
        Assert-False (Test-BTFixRadioInstanceId -InstanceId 'BTHENUM\DEV_1C5216F3AB89\7&88CFA05&0&BLUETOOTHDEVICE_1C5216F3AB89')
        Assert-False (Test-BTFixRadioInstanceId -InstanceId 'BTHLE\DEV_9C19C21B51AA\7&1C0AED2F&0&9C19C21B51AA')
        Assert-False (Test-BTFixRadioInstanceId -InstanceId 'BTH\MS_BTHBRB\6&216EF7FB&5&1')
        Assert-False (Test-BTFixRadioInstanceId -InstanceId 'BTH\MS_RFCOMM\6&47D89BF&2&0')
    }

    It 'accepts USB dongles and non-USB host radios' {
        Assert-True (Test-BTFixRadioInstanceId -InstanceId 'USB\VID_0A12&PID_0001\5&5E7D000&0&3')
        Assert-True (Test-BTFixRadioInstanceId -InstanceId 'PCI\VEN_8086&DEV_2723&SUBSYS_00308086')
        Assert-True (Test-BTFixRadioInstanceId -InstanceId 'SD\VID_0BDA&OID_0B77&REV_01.00\4&5B48B0C&0&2')
        Assert-True (Test-BTFixRadioInstanceId -InstanceId 'ACPI\QCOM0211\0')
    }
}

Describe 'superiority evaluation' {
    It 'maps LMP version numbers to standard Bluetooth specs' {
        Assert-Equal 'Bluetooth 4.0' (Get-BTFixLmpVersionName -LmpVersion 6)
        Assert-Equal 'Bluetooth 5.0' (Get-BTFixLmpVersionName -LmpVersion 9)
        Assert-Equal 'Bluetooth 5.1' (Get-BTFixLmpVersionName -LmpVersion 10)
        Assert-Equal 'Bluetooth 5.2' (Get-BTFixLmpVersionName -LmpVersion 11)
        Assert-Equal 'Bluetooth 5.3' (Get-BTFixLmpVersionName -LmpVersion 12)
        Assert-Equal 'Bluetooth 5.4' (Get-BTFixLmpVersionName -LmpVersion 13)
        Assert-Equal 'Bluetooth 6.0' (Get-BTFixLmpVersionName -LmpVersion 14)
    }

    It 'scores external dongle higher than internal radio when specs are equal' {
        $ext = Get-TestRadio -Id 'USB\EXT' -Name 'USB Dongle' -Internal $false -Lmp 10
        $int = Get-TestRadio -Id 'USB\INT' -Name 'Internal Radio' -Internal $true -Lmp 10
        $scoreExt = Get-BTFixRadioScore -Radio $ext
        $scoreInt = Get-BTFixRadioScore -Radio $int
        Assert-True ($scoreExt.Score -gt $scoreInt.Score) 'external dongle should outscore internal adapter with same LMP'
    }

    It 'prefers modern internal adapter over obsolete BT 2.1 external dongle' {
        $extOld = Get-TestRadio -Id 'USB\OLD' -Name 'Legacy Dongle' -Internal $false -Lmp 4
        $intNew = Get-TestRadio -Id 'USB\NEW' -Name 'Modern Internal' -Internal $true -Lmp 12
        $res = Get-BTFixSuperiorRadio -Radios @($extOld, $intNew)
        Assert-Equal 'USB\NEW' $res.SuperiorRadio.InstanceId
    }

    It 'selects external BT 5.1 dongle over internal BT 5.2 adapter for dedicated RF clearance' {
        $ext = Get-TestRadio -Id 'USB\DONGLE' -Name 'Generic Bluetooth Radio' -Internal $false -Lmp 10
        $int = Get-TestRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Internal $true -Lmp 11
        $res = Get-BTFixSuperiorRadio -Radios @($ext, $int)
        Assert-Equal 'USB\DONGLE' $res.SuperiorRadio.InstanceId
        Assert-True ($res.WinnerScore.Score -gt $res.RunnerUpScore.Score)
    }

    It 'handles single radio gracefully' {
        $single = Get-TestRadio -Id 'USB\SOLO' -Name 'Sole Radio'
        $res = Get-BTFixSuperiorRadio -Radios @($single)
        Assert-Equal 'USB\SOLO' $res.SuperiorRadio.InstanceId
        Assert-Match 'Only one' $res.Reason
    }

    It 'scores Bluetooth 4.0 < 4.1 < 4.2 monotonically' {
        $r40 = Get-BTFixRadioScore -Radio (Get-TestRadio -Id 'USB\A' -Lmp 6)
        $r41 = Get-BTFixRadioScore -Radio (Get-TestRadio -Id 'USB\B' -Lmp 7)
        $r42 = Get-BTFixRadioScore -Radio (Get-TestRadio -Id 'USB\C' -Lmp 8)
        Assert-True ($r40.Score -lt $r41.Score) "BT 4.0 ($($r40.Score)) should score below BT 4.1 ($($r41.Score))"
        Assert-True ($r41.Score -lt $r42.Score) "BT 4.1 ($($r41.Score)) should score below BT 4.2 ($($r42.Score))"
    }

    It 'heavily penalizes dongles with blocked drivers (code 48) so working internal radio wins' {
        $extBlocked = Get-TestRadio -Id 'USB\BLOCKED' -Name 'Broken Dongle' -Code 48 -Status 'Error' -Internal $false -Lmp 10
        $intWorking = Get-TestRadio -Id 'USB\INTERNAL' -Name 'Working Internal' -Code 0 -Status 'OK' -Internal $true -Lmp 10
        $res = Get-BTFixSuperiorRadio -Radios @($extBlocked, $intWorking)
        Assert-Equal 'USB\INTERNAL' $res.SuperiorRadio.InstanceId
        Assert-True ($res.WinnerScore.Score -gt $res.RunnerUpScore.Score)
    }
}

Describe 'radio targeting' {
    It 'refuses to repair when an explicit -Radio matches nothing (no fallback, no snapshot)' {
        # Read-only path: the early return happens before any mutation.
        $result = Invoke-BTFixRepair -Radio 'USB\DOES-NOT-EXIST'
        Assert-False $result.Healthy
        Assert-True ($null -eq $result.Backup)
        Assert-Equal 0 @($result.Steps).Count
    }
}

Describe 'integrity' {
    function New-IntegrityRoot {
        [CmdletBinding(SupportsShouldProcess)]
        param()
        $root = Join-Path ([IO.Path]::GetTempPath()) ('btfix-integrity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'BTFix.ps1') -Value 'fake entry script'
        return $root
    }

    It 'accepts an untouched tree against a file baseline' {
        $root = New-IntegrityRoot
        try {
            $hash = (Get-FileHash -LiteralPath (Join-Path $root 'BTFix.ps1') -Algorithm SHA256).Hash
            @{ 'BTFix.ps1' = $hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'file-hashes.json')
            $r = Test-BTFixIntegrity -ScriptRoot $root
            Assert-True $r.Ok
            Assert-Equal 'file' $r.BaselineSource
            Assert-Equal 0 @($r.Mismatches).Count
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'detects a modified file' {
        $root = New-IntegrityRoot
        try {
            $hash = (Get-FileHash -LiteralPath (Join-Path $root 'BTFix.ps1') -Algorithm SHA256).Hash
            @{ 'BTFix.ps1' = $hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'file-hashes.json')
            Set-Content -LiteralPath (Join-Path $root 'BTFix.ps1') -Value 'tampered!'
            $r = Test-BTFixIntegrity -ScriptRoot $root
            Assert-False $r.Ok
            Assert-Equal 1 @($r.Mismatches).Count
            Assert-True (@($r.Mismatches) -contains 'BTFix.ps1')
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'detects a file the baseline covers being deleted' {
        $root = New-IntegrityRoot
        try {
            @{ 'src\Health.psm1' = 'DEADBEEF' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'file-hashes.json')
            $r = Test-BTFixIntegrity -ScriptRoot $root
            Assert-False $r.Ok
            Assert-True (@($r.Missing) -contains 'src\Health.psm1')
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats a missing baseline as not-a-failure (dev tree, first run)' {
        $root = New-IntegrityRoot
        try {
            $r = Test-BTFixIntegrity -ScriptRoot $root
            Assert-True $r.Ok
            Assert-Equal 'none' $r.BaselineSource
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'repair pipeline (mocked)' {
    # Functions defined via ". $module {...}" are dot-sourced into the
    # module's own scope (plain "&" would run in a child scope and the
    # function definitions would die with it), so module-internal calls
    # resolve to these mocks: the whole repair pipeline runs without
    # pnputil, services, elevation, or sleeps.
    $btfixModule = Get-Module BTFix
    Assert-True ($null -ne $btfixModule) 'BTFix module not loaded'

    . $btfixModule {
        $script:PipelineMock = @{ Calls = 0; Pnp = @(); AlwaysConflict = $false }

        function New-PipelineRadio {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test mock: builds data, mutates nothing')]
            param([string]$Id, [string]$Name, [int]$Code, [string]$Status, [bool]$Internal)
            [pscustomobject]@{
                InstanceId = $Id; FriendlyName = $Name; Status = $Status
                ProblemCode = $Code; ProblemStatus = $null; DriverVersion = '1.0'
                DriverProvider = $null; HardwareIds = @('USB\VID_0A12&PID_0001')
                LocationInfo = ''; Parent = 'USB\ROOT_HUB30\X'
                IsInternal = $Internal
                IsHealthy = ($Status -eq 'OK' -and $Code -eq 0)
                IsDisabled = ($Code -eq 22)
            }
        }

        function Get-BTFixDiagnosis {
            $script:PipelineMock.Calls++
            $conflict = ($script:PipelineMock.Calls -eq 1) -or $script:PipelineMock.AlwaysConflict
            $dongleCode = if ($conflict) { 31 } else { 0 }
            $dongleStatus = if ($conflict) { 'Error' } else { 'OK' }
            $dongle = New-PipelineRadio -Id 'USB\DONGLE' -Name 'CSR Dongle' -Code $dongleCode -Status $dongleStatus -Internal $false
            $internal = New-PipelineRadio -Id 'USB\INTERNAL' -Name 'Realtek Bluetooth Adapter' -Code 0 -Status 'OK' -Internal $true
            $radios = @($dongle, $internal)
            return [pscustomobject]@{
                Classification     = 'mock'
                Confidence         = 'High'
                Radios             = $radios
                Healthy            = @($radios | Where-Object { $_.IsHealthy })
                Broken             = @($radios | Where-Object { -not $_.IsHealthy -and -not $_.IsDisabled })
                Disabled           = @($radios | Where-Object { $_.IsDisabled })
                Evidence           = @('mock evidence')
                RecommendedActions = @('mock action')
            }
        }

        # The real safety guard reads the device class through Get-PnpDevice;
        # the mock answers Bluetooth for radio-shaped ids, Net otherwise, and
        # an empty inventory for live enumerations (-Class calls).
        function Get-PnpDevice {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test mock: the safety guard must be exercised under its real name')]
            param($InstanceId, $Class)
            if ($Class) { return $null }
            $class = if ($InstanceId -like 'USB\*') { 'Bluetooth' } else { 'Net' }
            [pscustomobject]@{ Class = $class; InstanceId = $InstanceId }
        }

        function Get-BTFixServiceHealth {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test mock: never mutates anything')]
            param()
            return @()
        }
        function Restart-BTFixStack {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test mock: never mutates anything')]
            param()
            return $false
        }
        function Restart-BTFixAudioStack {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test mock: never mutates anything')]
            param()
        }
        function Invoke-BTFixRescan {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test mock: never mutates anything')]
            param()
            $null = (& $script:BTFixPnpRunner -PnpArguments @('/scan-devices'))
            return $true
        }
    }

    function Reset-PipelineMock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper: resets mock counters only')]
        param()
        & $btfixModule {
            $script:PipelineMock.Calls = 0
            $script:PipelineMock.Pnp = @()
            $script:PipelineMock.AlwaysConflict = $false
            $script:BTFixRebootRequired = $false
            $script:BTFixPnpRunner = {
                param([string[]]$PnpArguments)
                $script:PipelineMock.Pnp += ,@($PnpArguments)
                $global:LASTEXITCODE = 0
                return 'MOCKED PNP OUTPUT'
            }
        }
    }

    It 'runs the conflict repair sequence: park internal, remove broken dongle, rescan' {
        Reset-PipelineMock
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-pipeline-' + [guid]::NewGuid().ToString('N'))
        try {
            $result = Invoke-BTFixRepair -Radio 'USB\DONGLE' -BackupPath $dir
            Assert-True $result.Healthy
            Assert-True ($result.Steps -contains 'disabled USB\INTERNAL')
            $backup = & $btfixModule { $script:PipelineMock.Pnp }
            Assert-Equal '/disable-device' $backup[0][0]
            Assert-Equal 'USB\INTERNAL'    $backup[0][1]
            Assert-Equal '/remove-device'  $backup[1][0]
            Assert-Equal 'USB\DONGLE'      $backup[1][1]
            Assert-Equal '/scan-devices'   $backup[2][0]
            Assert-True (Test-Path -LiteralPath $result.Backup) 'expected a snapshot file'
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps the working internal radio when -PreferInternal is set and the dongle stays broken' {
        Reset-PipelineMock
        & $btfixModule { $script:PipelineMock.AlwaysConflict = $true }
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-pipeline-' + [guid]::NewGuid().ToString('N'))
        try {
            $result = Invoke-BTFixRepair -PreferInternal -BackupPath $dir
            Assert-False $result.Healthy
            Assert-True (@($result.Steps | Where-Object { $_ -like 'kept the working radio*' }).Count -ge 1)
            $calls = & $btfixModule { $script:PipelineMock.Pnp }
            Assert-Equal '/remove-device' $calls[0][0]
            Assert-Equal 'USB\DONGLE'     $calls[0][1]
            Assert-Equal 0 @($calls | Where-Object { $_[0] -eq '/disable-device' }).Count 'no radio should be disabled when the preferred one is healthy'
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'safety guard refuses to mutate non-Bluetooth devices' {
        Reset-PipelineMock
        $threw = $false
        try {
            # Invoke-BTFixPnp is internal to the module: call it in module scope.
            $null = & $btfixModule { Invoke-BTFixPnp -Arguments @('/disable-device', 'PCI\VEN_1234&DEV_5678') } 2>$null
        } catch {
            $threw = $true
        }
        Assert-True $threw 'expected the safety guard to throw for a non-Bluetooth target'
        $calls = & $btfixModule { $script:PipelineMock.Pnp }
        Assert-Equal 0 @($calls).Count 'the runner must not be called for a blocked target'
    }

    It 'flags a reboot when the runner reports pnputil exit 3010' {
        Reset-PipelineMock
        & $btfixModule {
            $script:BTFixPnpRunner = {
                param([string[]]$PnpArguments)
                $global:LASTEXITCODE = 3010
                return "reboot required (mocked): $($PnpArguments -join ' ')"
            }
        }
        $null = & $btfixModule { Invoke-BTFixPnp -Arguments @('/enable-device', 'USB\DONGLE') }
        $flagged = & $btfixModule { $script:BTFixRebootRequired }
        Assert-True $flagged 'exit 3010 must set the reboot-required flag'
    }
    It 'refuses a second repair while one holds the lock' {
        Reset-PipelineMock
        # Mutexes are re-entrant on the owning THREAD, so the holder must be
        # a different thread - a runspace - not this one.
        $holder = [powershell]::Create()
        $null = $holder.AddScript({
            $m = [System.Threading.Mutex]::new($false, 'Local\BTFix-Repair')
            $null = $m.WaitOne(3000)
            Start-Sleep -Milliseconds 600
            $null = $m.ReleaseMutex()
            $m.Dispose()
        })
        $handle = $holder.BeginInvoke()
        Start-Sleep -Milliseconds 200  # let the holder take the lock first
        try {
            $repair = Invoke-BTFixRepair -BackupPath (Join-Path ([IO.Path]::GetTempPath()) 'btfix-lock-test')
            Assert-True $repair.LockFailed
            Assert-Equal 0 @($repair.Steps).Count
            $rollback = Invoke-BTFixRollback -BackupPath (Join-Path ([IO.Path]::GetTempPath()) 'btfix-lock-test')
            Assert-True $rollback.LockFailed
        } finally {
            $null = $handle.AsyncWaitHandle.WaitOne(5000)
            $holder.Dispose()
        }
        # the lock is free again: the wrapper proceeds (with the mocked
        # pipeline still installed, nothing mutates)
        $again = Invoke-BTFixRollback -BackupPath (Join-Path ([IO.Path]::GetTempPath()) 'btfix-lock-test')
        Assert-False $again.LockFailed
    }
}

Describe 'handsfree hi-fi enforcer' {
    It 'queries hands-free devices without error' {
        $devices = @(Get-BTFixHandsFreeDevice)
        Assert-True ($devices -is [array])
    }

    It 'supports -WhatIf when disabling or enabling hands-free state' {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-hf-' + [guid]::NewGuid().ToString('N'))
        try {
            $res = Set-BTFixHandsFreeState -State 'Disable' -BackupPath $tempDir -WhatIf
            Assert-True ($null -ne $res)
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'battery telemetry' {
    It 'queries peripheral battery status without throwing' {
        $bats = @(Get-BTFixBatteryStatus)
        Assert-True ($bats -is [array])
        foreach ($b in $bats) {
            Assert-True ($null -ne $b.FriendlyName)
            Assert-True ($null -ne $b.Gauge)
            Assert-True ($b.HasBatteryInfo -is [bool])
        }
    }
}

Describe 'audio codec optimizer' {
    It 'reads audio codec configuration' {
        $info = Get-BTFixAudioCodecInfo
        Assert-True ($null -ne $info)
        Assert-True ($info.AacEnabled -is [bool])
        Assert-True ($info.AptxEnabled -is [bool])
        Assert-True ($info.AbsoluteVolumeDisabled -is [bool])
    }

    It 'supports -WhatIf for codec preference changes' {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('btfix-codec-' + [guid]::NewGuid().ToString('N'))
        try {
            $ok = Set-BTFixAudioCodecPreference -EnableAac -EnableAptx -BackupPath $tempDir -WhatIf
            Assert-True ($ok -is [bool])
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'gaming controller latency' {
    It 'detects controllers without throwing' {
        $ctrls = @(Get-BTFixGamingController)
        Assert-True ($ctrls -is [array])
    }

    It 'supports -WhatIf for controller latency optimization' {
        $res = Optimize-BTFixControllerLatency -WhatIf
        Assert-True ($null -ne $res)
    }
}

Write-Summary
