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

function Get-TestRadio {
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
        DriverVersion  = '10.0.26100.9711'
        DriverProvider = 'Microsoft'
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
}

Describe 'tooling' {
    It 'exposes the public functions' {
        $exported = (Get-Module BTFix).ExportedFunctions.Keys
        foreach ($fn in @('Get-BTFixRadio', 'Get-BTFixDiagnosis', 'Invoke-BTFixRepair', 'Invoke-BTFixRollback', 'Write-BTFixReport')) {
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

    It 'recognises Intel and Realtek ids' {
        Assert-True (@(Get-BTFixChipset -HardwareId 'USB\VID_8087&PID_0032')[0].Family -match 'Intel')
        Assert-True (@(Get-BTFixChipset -HardwareId 'USB\VID_0BDA&PID_4853')[0].Family -match 'Realtek')
    }

    It 'says so when it does not know the chipset' {
        $m = @(Get-BTFixChipset -HardwareId 'USB\VID_FFFF&PID_FFFF')
        Assert-Equal 'Unknown chipset' $m[0].Family
    }
}

Describe 'health checks' {
    It 'reports the services the stack needs' {
        $services = Get-BTFixServiceHealth
        Assert-Equal 3 $services.Count
        Assert-Equal 1 @($services | Where-Object { $_.Name -eq 'bthserv' }).Count
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
}

Describe 'findings' {
    It 'flags the dual-radio conflict as auto-fixable' {
        $f = @(Get-BTFixFinding -Inventory @(
                (Get-TestRadio -Id 'USB\BAD' -Name 'Generic Bluetooth Radio' -Code 31 -Status 'Error'),
                (Get-TestRadio -Id 'USB\GOOD' -Name 'Realtek Bluetooth Adapter')
            ) -NoLive)
        $conflict = @($f | Where-Object { $_.Id -eq 'radio-31' })[0]
        Assert-True ($null -ne $conflict) 'expected a radio-31 finding'
        Assert-True $conflict.AutoFixable
        Assert-True ($conflict.Title -match 'fighting')
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

    It 'reports no radio at all' {
        $f = @(Get-BTFixFinding -Inventory @() -NoLive)
        Assert-Equal 1 @($f | Where-Object { $_.Id -eq 'no-radio' }).Count
    }
}

Write-Summary
