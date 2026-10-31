<#
.SYNOPSIS
    BTFix Sentry — Windows System Tray Background Monitor
.DESCRIPTION
    Zero-dependency background notification area daemon for Bluetooth Dongle Fix.
    Hooks hardware PnP changes, automatically resolves dual-radio (Code 31) conflicts
    when new dongles are plugged in, alerts on high USB 3.0 RF interference, and sends
    low-battery notifications when peripheral charge drops below 15%.
#>

[CmdletBinding()]
param(
    [switch]$NoAutoRepair,

    # Verify initialization, build context menus, run one scan cycle, and exit cleanly.
    [switch]$SelfTest
)

Set-StrictMode -Off

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }

# Import core modules
Import-Module (Join-Path $scriptRoot 'src\Findings.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Health.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Chipsets.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\ProblemCodes.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Superiority.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\BTFix.psm1') -Force

# Verify integrity before running
$integrity = Test-BTFixIntegrity -ScriptRoot $scriptRoot
if (-not $integrity.Ok) {
    $detail = "BTFix integrity check failed:`n" +
        ($integrity.Mismatches | ForEach-Object { "  modified: $_" } | Out-String) +
        ($integrity.Missing | ForEach-Object { "  missing: $_" } | Out-String)
    if ($SelfTest) {
        Write-Error $detail
        exit 3
    }
    [System.Windows.Forms.MessageBox]::Show($detail, 'BTFix Sentry - Integrity Error',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    exit 3
}

$script:GuiScript = Join-Path $scriptRoot 'BTFix-GUI.ps1'
$script:CliScript = Join-Path $scriptRoot 'BTFix.ps1'
$script:AutoRepairEnabled = -not [bool]$NoAutoRepair
$script:LastKnownRadios = @()
$script:LastRadioFingerprint = ''
$script:AlertedLowBatteries = @{}
$script:AlertedRfDongles = @{}

# Extract native Windows Bluetooth icon from fsquirt.exe or fallback to SystemIcon
$trayIcon = $null
$fsquirt = Join-Path $env:SystemRoot 'System32\fsquirt.exe'
if (Test-Path -LiteralPath $fsquirt) {
    try {
        $trayIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($fsquirt)
    } catch {
        $trayIcon = $null
    }
}
if (-not $trayIcon) {
    $trayIcon = [System.Drawing.SystemIcons]::Application
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $trayIcon
$notifyIcon.Text = "BTFix - Bluetooth Sentry v2.1"

# ----------------- Context Menu -----------------
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# 1. Header
$itemHeader = New-Object System.Windows.Forms.ToolStripMenuItem("BTFix Sentry v2.1")
$itemHeader.Enabled = $false
$itemHeader.Font = New-Object System.Drawing.Font($contextMenu.Font, [System.Drawing.FontStyle]::Bold)
$null = $contextMenu.Items.Add($itemHeader)

$null = $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 2. Open GUI Dashboard
$itemGui = New-Object System.Windows.Forms.ToolStripMenuItem("Open Dashboard")
$itemGui.Font = New-Object System.Drawing.Font($contextMenu.Font, [System.Drawing.FontStyle]::Bold)
$itemGui.Add_Click({
    if (Test-Path -LiteralPath $script:GuiScript) {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:GuiScript`"") -WindowStyle Normal
    }
})
$null = $contextMenu.Items.Add($itemGui)

# 3. Quick Repair
function Invoke-TrayQuickRepair {
    $notifyIcon.ShowBalloonTip(3000, "BTFix - Repairing Stack", "Executing conflict repair and radio binding...", [System.Windows.Forms.ToolTipIcon]::Info)
    try {
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScript`"", '-Mode', 'Fix') -Verb RunAs -PassThru -WindowStyle Hidden
        $p.WaitForExit(30000)
        $diag = Get-BTFixDiagnosis
        if ($diag.Classification -in @('Healthy', 'HealthyWithDisabledRadio')) {
            $notifyIcon.ShowBalloonTip(4000, "BTFix - Repair Succeeded", "Bluetooth stack is healthy. Superior radio is active.", [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            $notifyIcon.ShowBalloonTip(4000, "BTFix - Repair Finished", "Repair sequence executed. Run Dashboard for details.", [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    } catch {
        $notifyIcon.ShowBalloonTip(4000, "BTFix - Elevation Required", "Administrator rights are required to repair hardware.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

$itemRepair = New-Object System.Windows.Forms.ToolStripMenuItem("Quick Repair (Fix Conflict)")
$itemRepair.Add_Click({ Invoke-TrayQuickRepair })
$null = $contextMenu.Items.Add($itemRepair)

# 4. Run Health Check
$itemDiag = New-Object System.Windows.Forms.ToolStripMenuItem("Run Health Check")
$itemDiag.Add_Click({
    $radios = @(Get-BTFixRadio)
    $diag = Get-BTFixDiagnosis -Inventory $radios
    $isConflict = ($diag.Classification -eq 'RadioConflictOrDriverStartFailure' -and $diag.Healthy.Count -gt 0)
    $tipText = if ($diag.Classification -in @('Healthy', 'HealthyWithDisabledRadio')) {
        "$($radios.Count) radio(s) active. Stack is healthy."
    } elseif ($isConflict) {
        "Dual-radio conflict detected! Click Quick Repair."
    } else {
        "Diagnosis: $($diag.Classification). Open Dashboard for details."
    }
    $tipIcon = if ($diag.Classification -in @('Healthy', 'HealthyWithDisabledRadio')) { [System.Windows.Forms.ToolTipIcon]::Info } else { [System.Windows.Forms.ToolTipIcon]::Warning }
    $notifyIcon.ShowBalloonTip(4000, "BTFix Health Check", $tipText, $tipIcon)
})
$null = $contextMenu.Items.Add($itemDiag)

$null = $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 5. Audio & Telephony Mode Submenu
$menuAudio = New-Object System.Windows.Forms.ToolStripMenuItem("Anti-HandsFree Hi-Fi")

$itemHfDisable = New-Object System.Windows.Forms.ToolStripMenuItem("Disable Hands-Free (Lock Hi-Fi Stereo)")
$itemHfDisable.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScript`"", '-Mode', 'HandsFree', '-State', 'Disable') -Verb RunAs -WindowStyle Hidden -Wait
        $notifyIcon.ShowBalloonTip(3000, "BTFix - Hands-Free Isolated", "Virtual telephony disabled. Hi-Fi A2DP stereo locked.", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $notifyIcon.ShowBalloonTip(3000, "BTFix", "Admin elevation required to modify telephony profile.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$null = $menuAudio.DropDownItems.Add($itemHfDisable)

$itemHfEnable = New-Object System.Windows.Forms.ToolStripMenuItem("Enable Hands-Free (Allow Telephony Mic)")
$itemHfEnable.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScript`"", '-Mode', 'HandsFree', '-State', 'Enable') -Verb RunAs -WindowStyle Hidden -Wait
        $notifyIcon.ShowBalloonTip(3000, "BTFix - Hands-Free Restored", "Telephony mic profiles re-enabled.", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $notifyIcon.ShowBalloonTip(3000, "BTFix", "Admin elevation required to modify telephony profile.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$null = $menuAudio.DropDownItems.Add($itemHfEnable)

$null = $contextMenu.Items.Add($menuAudio)

# 6. Bluetooth LE Audio (LC3) Submenu
$menuLe = New-Object System.Windows.Forms.ToolStripMenuItem("Bluetooth LE Audio (LC3)")

$itemLeEnable = New-Object System.Windows.Forms.ToolStripMenuItem("Enable LE Audio (Prefer LC3 / Auracast)")
$itemLeEnable.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScript`"", '-Mode', 'LEAudio', '-State', 'Enable') -Verb RunAs -WindowStyle Hidden -Wait
        $notifyIcon.ShowBalloonTip(3000, "BTFix - LE Audio Enabled", "Policy configured to prefer LC3 & Auracast.", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $notifyIcon.ShowBalloonTip(3000, "BTFix", "Admin elevation required to configure LE Audio.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$null = $menuLe.DropDownItems.Add($itemLeEnable)

$itemLeDisable = New-Object System.Windows.Forms.ToolStripMenuItem("Disable LE Audio (Classic Audio Fallback)")
$itemLeDisable.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScript`"", '-Mode', 'LEAudio', '-State', 'Disable') -Verb RunAs -WindowStyle Hidden -Wait
        $notifyIcon.ShowBalloonTip(3000, "BTFix - Classic Audio Fallback", "Policy configured to force Classic Audio.", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $notifyIcon.ShowBalloonTip(3000, "BTFix", "Admin elevation required to configure LE Audio.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$null = $menuLe.DropDownItems.Add($itemLeDisable)

$null = $contextMenu.Items.Add($menuLe)

# 7. Peripherals & Battery Submenu
$menuBattery = New-Object System.Windows.Forms.ToolStripMenuItem("Peripherals & Battery")
$menuBattery.Add_DropDownOpening({
    $menuBattery.DropDownItems.Clear()
    $peripherals = @(Get-BTFixBatteryStatus)
    if ($peripherals.Count -eq 0) {
        $emptyItem = New-Object System.Windows.Forms.ToolStripMenuItem("No paired peripherals found")
        $emptyItem.Enabled = $false
        $null = $menuBattery.DropDownItems.Add($emptyItem)
    } else {
        foreach ($p in $peripherals) {
            $connText = if ($p.IsConnected) { "Connected" } else { "Offline" }
            $batText = if ($p.HasBatteryInfo) { "$($p.BatteryPercent)%" } else { "No battery data" }
            $lbl = "$($p.FriendlyName) ($connText - $batText)"
            $sub = New-Object System.Windows.Forms.ToolStripMenuItem($lbl)
            $sub.Enabled = $false
            $null = $menuBattery.DropDownItems.Add($sub)
        }
    }
})
$null = $contextMenu.Items.Add($menuBattery)

$null = $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 8. Auto-Repair Toggle
$itemAuto = New-Object System.Windows.Forms.ToolStripMenuItem("Auto-Repair Dual-Radio Conflicts")
$itemAuto.CheckOnClick = $true
$itemAuto.Checked = $script:AutoRepairEnabled
$itemAuto.Add_Click({
    $script:AutoRepairEnabled = $itemAuto.Checked
})
$null = $contextMenu.Items.Add($itemAuto)

# 9. Exit
$null = $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit BTFix Sentry")
$itemExit.Add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if ($script:HardwareTimer) { $script:HardwareTimer.Stop(); $script:HardwareTimer.Dispose() }
    if ($script:BatteryTimer) { $script:BatteryTimer.Stop(); $script:BatteryTimer.Dispose() }
    [System.Windows.Forms.Application]::Exit()
})
$null = $contextMenu.Items.Add($itemExit)

$notifyIcon.ContextMenuStrip = $contextMenu

# Double-click or Balloon-click opens GUI Dashboard
$notifyIcon.Add_DoubleClick({
    if (Test-Path -LiteralPath $script:GuiScript) {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:GuiScript`"") -WindowStyle Normal
    }
})
$notifyIcon.Add_BalloonTipClicked({
    if (Test-Path -LiteralPath $script:GuiScript) {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:GuiScript`"") -WindowStyle Normal
    }
})

# ----------------- Scan & Sentry Logic -----------------
function Invoke-BTFixHardwareSentry {
    $radios = @(Get-BTFixRadio)
    $fingerprint = ($radios | ForEach-Object { "$($_.InstanceId):$($_.Status):$($_.ProblemCode)" }) -join '|'

    if ($fingerprint -ne $script:LastRadioFingerprint) {
        $script:LastRadioFingerprint = $fingerprint
        $diag = Get-BTFixDiagnosis -Inventory $radios
    $isConflict = ($diag.Classification -eq 'RadioConflictOrDriverStartFailure' -and $diag.Healthy.Count -gt 0)

        if ($isConflict) {
            if ($script:AutoRepairEnabled) {
                $notifyIcon.ShowBalloonTip(5000, "BTFix - Dual-Radio Conflict Detected",
                    "External dongle collision (Code 31) detected. Automatically triggering repair...",
                    [System.Windows.Forms.ToolTipIcon]::Warning)
                Invoke-TrayQuickRepair
            } else {
                $notifyIcon.ShowBalloonTip(7000, "BTFix - Dual-Radio Conflict Detected",
                    "External dongle is blocked by internal radio (Code 31). Click here to repair.",
                    [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        } else {
            # Check for high USB 3.0 RF interference risk on newly arrived dongles
            if (Get-Command 'Get-BTFixUsbTopology' -ErrorAction SilentlyContinue) {
                $topologies = @(Get-BTFixUsbTopology -Radios $radios | Where-Object { $_.IsUsbDongle -and $_.RfRisk -eq 'High' })
                foreach ($top in $topologies) {
                    if (-not $script:AlertedRfDongles.ContainsKey($top.InstanceId)) {
                        $script:AlertedRfDongles[$top.InstanceId] = [DateTime]::UtcNow
                        $notifyIcon.ShowBalloonTip(6000, "BTFix - USB 3.0 RF Interference",
                            "$($top.RadioName) is on a USB 3.0 port with active storage traffic. Spread-spectrum noise can cause audio stutters.",
                            [System.Windows.Forms.ToolTipIcon]::Warning)
                    }
                }
            }
        }
    }
}

function Invoke-BTFixBatterySentry {
    $peripherals = @(Get-BTFixBatteryStatus | Where-Object { $_.HasBatteryInfo -and $_.IsConnected })
    $now = [DateTime]::UtcNow

    # Update tray tooltip with primary connected device battery
    if ($peripherals.Count -gt 0) {
        $p1 = $peripherals[0]
        $trayText = "BTFix: $($p1.FriendlyName) ($($p1.BatteryPercent)%)"
        if ($trayText.Length -gt 63) { $trayText = $trayText.Substring(0, 60) + '...' }
        $notifyIcon.Text = $trayText
    } else {
        $notifyIcon.Text = "BTFix - Bluetooth Sentry v2.1"
    }

    # Low battery warnings (<= 15%)
    foreach ($p in $peripherals) {
        if ($p.BatteryPercent -le 15) {
            $lastAlert = if ($script:AlertedLowBatteries.ContainsKey($p.InstanceId)) { $script:AlertedLowBatteries[$p.InstanceId] } else { [DateTime]::MinValue }
            if (($now - $lastAlert).TotalMinutes -ge 30) {
                $script:AlertedLowBatteries[$p.InstanceId] = $now
                $notifyIcon.ShowBalloonTip(5000, "Low Battery Alert",
                    "$($p.FriendlyName) is at $($p.BatteryPercent)%. Please charge to prevent disconnects.",
                    [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        } elseif ($p.BatteryPercent -gt 25) {
            $script:AlertedLowBatteries.Remove($p.InstanceId)
        }
    }
}

# ----------------- SelfTest / Headless Mode -----------------
if ($SelfTest) {
    try {
        Invoke-BTFixHardwareSentry
        Invoke-BTFixBatterySentry
        $itemCount = $contextMenu.Items.Count
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        Write-Host ("SELFTEST OK tray initialized items={0}" -f $itemCount)
        exit 0
    } catch {
        Write-Host "SELFTEST FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($notifyIcon) { $notifyIcon.Visible = $false; $notifyIcon.Dispose() }
        exit 1
    }
}

# ----------------- Production Background Loop -----------------
$notifyIcon.Visible = $true

# Hardware check every 3.5 seconds
$script:HardwareTimer = New-Object System.Windows.Forms.Timer
$script:HardwareTimer.Interval = 3500
$script:HardwareTimer.Add_Tick({ Invoke-BTFixHardwareSentry })
$script:HardwareTimer.Start()

# Battery telemetry check every 45 seconds
$script:BatteryTimer = New-Object System.Windows.Forms.Timer
$script:BatteryTimer.Interval = 45000
$script:BatteryTimer.Add_Tick({ Invoke-BTFixBatterySentry })
$script:BatteryTimer.Start()

# Initial scan
Invoke-BTFixHardwareSentry
Invoke-BTFixBatterySentry

$notifyIcon.ShowBalloonTip(3000, "BTFix Sentry Active", "Monitoring Bluetooth hardware, RF interference, and peripheral battery levels.", [System.Windows.Forms.ToolTipIcon]::Info)

[System.Windows.Forms.Application]::Run()
