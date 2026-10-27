@{
    RootModule        = 'BTFix.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'b7f0c2a4-9d3e-4c1a-8f5b-2e6d0a1c7f43'
    Author            = 'Saman Ghorayshi'
    CompanyName       = 'BTFix contributors'
    Copyright         = '(c) 2026 BTFix contributors. MIT licensed.'
    Description       = 'Diagnose and repair USB Bluetooth dongles that Windows refuses to start (Code 31 / CM_PROB_FAILED_ADD), usually caused by a dual-radio conflict.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-BTFixRadio', 'Get-BTFixDiagnosis', 'New-BTFixBackup', 'Get-BTFixLatestBackup',
        'Invoke-BTFixRepair', 'Invoke-BTFixRollback', 'Invoke-BTFixWindowsUpdate',
        'Write-BTFixReport', 'Write-BTFixReportJson', 'Write-BTFixLog', 'Test-BTFixAdministrator',
        'Get-BTFixStateRoot', 'Test-BTFixInternalRadio', 'Test-BTFixRadioInstanceId',
        'Resolve-BTFixWantedRadio', 'Restart-BTFixAudioStack', 'Get-BTFixLmpVersionName',
        'Get-BTFixRadioScore', 'Get-BTFixSuperiorRadio'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Get-BTFixRadioSpecs')
    PrivateData       = @{
        PSData = @{
            Tags       = @('Bluetooth', 'Driver', 'Windows', 'Repair', 'Code31')
            ProjectUri = 'https://github.com/Saman-ghorayshi/bluetooth-dongle-fix'
            LicenseUri = 'https://github.com/Saman-ghorayshi/bluetooth-dongle-fix/blob/main/LICENSE'
        }
    }
}
