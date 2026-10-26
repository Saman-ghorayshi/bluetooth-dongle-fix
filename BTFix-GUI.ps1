<#
.SYNOPSIS
    Bluetooth Dongle Fix — Modern Graphical User Interface (WPF / XAML)
.DESCRIPTION
    Zero-dependency native Windows GUI for diagnosing dual-radio conflicts,
    running the Superiority Benchmark Engine, resolving Code 31/43/10/22
    lockouts, and restoring stutter-free audio to wireless earbuds.
#>

[CmdletBinding()]
param(
    [switch]$AutoScan
)

Set-StrictMode -Off

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }

# Import core modules
Import-Module (Join-Path $scriptRoot 'src\Findings.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Health.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Chipsets.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\ProblemCodes.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\Superiority.psm1') -Force
Import-Module (Join-Path $scriptRoot 'src\BTFix.psm1') -Force

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Bluetooth Dongle Fix &amp; Superiority Benchmark"
        Height="760" Width="980" MinHeight="640" MinWidth="840"
        WindowStartupLocation="CenterScreen"
        Background="#0D1117" Foreground="#C9D1D9"
        FontFamily="Segoe UI, Segoe UI Variable, Arial">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#F0F6FC"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#30363D"/>
                                <Setter Property="BorderBrush" Value="#8B949E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#161B22"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#238636"/>
            <Setter Property="BorderBrush" Value="#2EA043"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#2EA043"/>
                                <Setter Property="BorderBrush" Value="#3FB950"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#1F7F34"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="1.1*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="0.9*"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="🎧 Bluetooth Dongle Fix" FontSize="20" FontWeight="Bold" Foreground="#58A6FF"/>
                    <Border Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="4" Margin="12,2,0,0" Padding="6,1">
                        <TextBlock Text="v2.0" FontSize="11" FontWeight="Bold" Foreground="#8B949E"/>
                    </Border>
                </StackPanel>
                <TextBlock Text="Dual-Radio Conflict Resolver &amp; Superiority Benchmark Engine" FontSize="12" Foreground="#8B949E" Margin="0,3,0,0"/>
            </StackPanel>

            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <Border x:Name="BadgeAdmin" CornerRadius="6" Padding="10,5" Margin="0,0,8,0" BorderThickness="1">
                    <TextBlock x:Name="TxtAdmin" FontSize="12" FontWeight="SemiBold"/>
                </Border>
                <Button x:Name="BtnElevate" Content="🛡️ Elevate as Admin" Padding="10,5" Visibility="Collapsed"/>
            </StackPanel>
        </Grid>

        <!-- Diagnosis Banner -->
        <Border x:Name="BorderDiagnosis" Grid.Row="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12" BorderThickness="1" Background="#161B22" BorderBrush="#30363D">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="TxtDiagnosisIcon" Text="⚡" FontSize="18" Margin="0,0,10,0" VerticalAlignment="Center"/>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock x:Name="TxtDiagnosisTitle" Text="Initializing scan..." FontWeight="Bold" FontSize="13" Foreground="#F0F6FC"/>
                    <TextBlock x:Name="TxtDiagnosisDetail" Text="Scanning PnP device tree and radio controllers..." FontSize="12" Foreground="#8B949E" Margin="0,2,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Cards View (Radios + Peripherals) -->
        <Grid Grid.Row="2" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.2*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="0.9*"/>
            </Grid.ColumnDefinitions>

            <!-- Radios Column -->
            <Border Grid.Column="0" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="8" Padding="14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <DockPanel Grid.Row="0" Margin="0,0,0,10">
                        <TextBlock Text="📡 Bluetooth Host Radios" FontWeight="Bold" FontSize="13" Foreground="#F0F6FC"/>
                        <TextBlock x:Name="TxtRadioCount" Text="0 found" HorizontalAlignment="Right" FontSize="11" Foreground="#8B949E"/>
                    </DockPanel>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="PanelRadios" Margin="0,0,4,0"/>
                    </ScrollViewer>
                </Grid>
            </Border>

            <!-- Peripherals Column -->
            <Border Grid.Column="2" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="8" Padding="14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <DockPanel Grid.Row="0" Margin="0,0,0,10">
                        <TextBlock Text="🎧 Audio &amp; Peripherals" FontWeight="Bold" FontSize="13" Foreground="#F0F6FC"/>
                        <TextBlock x:Name="TxtPeripheralCount" Text="0 found" HorizontalAlignment="Right" FontSize="11" Foreground="#8B949E"/>
                    </DockPanel>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="PanelPeripherals" Margin="0,0,4,0"/>
                    </ScrollViewer>
                </Grid>
            </Border>
        </Grid>

        <!-- Action Command Bar -->
        <Border Grid.Row="3" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,0,0,12">
            <WrapPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnAutoFix" Style="{StaticResource PrimaryButton}" Content="⚡ One-Click Auto-Fix" Margin="0,0,8,0" ToolTip="Automatically benchmarks radios, isolates superior radio, parks conflicting radio, and resets audio stack."/>
                <Button x:Name="BtnScan" Content="🔍 Scan &amp; Benchmark" Margin="0,0,8,0" ToolTip="Refreshes hardware inventory and recalculates superiority scores."/>
                <Button x:Name="BtnRestartAudio" Content="🎧 Fix Audio Drops" Margin="0,0,8,0" ToolTip="Restarts BTAGService and Windows AudioEndpointBuilder to re-route audio to earbuds without rebooting."/>
                <Button x:Name="BtnRollback" Content="🔄 Rollback" Margin="0,0,8,0" ToolTip="Restores hardware state from the latest backup snapshot."/>
                <Button x:Name="BtnExport" Content="📋 Export Report" Margin="0,0,16,0" ToolTip="Generates a full Markdown &amp; JSON diagnostics bundle."/>
                
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,0,0">
                    <CheckBox x:Name="ChkPreferInternal" Content="Prefer Internal Adapter" Foreground="#C9D1D9" Margin="0,0,12,0" VerticalAlignment="Center" ToolTip="Forces priority to internal motherboard radio instead of external USB dongle."/>
                    <CheckBox x:Name="ChkDisableUsbSuspend" Content="Disable USB Suspend" Foreground="#C9D1D9" VerticalAlignment="Center" ToolTip="Prevents Windows Selective Suspend from powering off USB dongle during idle."/>
                </StackPanel>
            </WrapPanel>
        </Border>

        <!-- Live Activity Log -->
        <Border Grid.Row="4" Background="#0D1117" BorderBrush="#30363D" BorderThickness="1" CornerRadius="8" Padding="12,8">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <DockPanel Grid.Row="0" Margin="0,0,0,6">
                    <TextBlock Text="📜 Live Activity Log" FontWeight="Bold" FontSize="12" Foreground="#8B949E"/>
                    <Button x:Name="BtnClearLog" Content="Clear" HorizontalAlignment="Right" Padding="6,2" FontSize="11"/>
                </DockPanel>
                <RichTextBox x:Name="TxtConsole" Grid.Row="1" Background="#090D13" Foreground="#C9D1D9"
                             BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                             FontFamily="Consolas, Courier New, monospace" FontSize="12">
                    <FlowDocument PagePadding="4" LineHeight="18"/>
                </RichTextBox>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Map controls
$badgeAdmin           = $window.FindName('BadgeAdmin')
$txtAdmin             = $window.FindName('TxtAdmin')
$btnElevate           = $window.FindName('BtnElevate')
$borderDiagnosis      = $window.FindName('BorderDiagnosis')
$txtDiagnosisIcon     = $window.FindName('TxtDiagnosisIcon')
$txtDiagnosisTitle    = $window.FindName('TxtDiagnosisTitle')
$txtDiagnosisDetail   = $window.FindName('TxtDiagnosisDetail')
$panelRadios          = $window.FindName('PanelRadios')
$panelPeripherals     = $window.FindName('PanelPeripherals')
$txtRadioCount        = $window.FindName('TxtRadioCount')
$txtPeripheralCount   = $window.FindName('TxtPeripheralCount')
$btnAutoFix           = $window.FindName('BtnAutoFix')
$btnScan              = $window.FindName('BtnScan')
$btnRestartAudio      = $window.FindName('BtnRestartAudio')
$btnRollback          = $window.FindName('BtnRollback')
$btnExport            = $window.FindName('BtnExport')
$chkPreferInternal    = $window.FindName('ChkPreferInternal')
$chkDisableUsbSuspend = $window.FindName('ChkDisableUsbSuspend')
$txtConsole           = $window.FindName('TxtConsole')
$btnClearLog          = $window.FindName('BtnClearLog')

# Brush converter
$brushConv = [System.Windows.Media.BrushConverter]::new()

function Invoke-DispatcherUI {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Write-GuiLog {
    param(
        [string]$Level = 'INFO',
        [string]$Message
    )
    $time = (Get-Date).ToString('HH:mm:ss')
    $p = New-Object System.Windows.Documents.Paragraph
    $p.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)

    $rTime = New-Object System.Windows.Documents.Run("[$time] ")
    $rTime.Foreground = $brushConv.ConvertFromString('#6E7681')
    $p.Inlines.Add($rTime)

    $color = switch ($Level) {
        'OK'     { '#3FB950' }
        'INFO'   { '#58A6FF' }
        'WARN'   { '#D29922' }
        'ERROR'  { '#F85149' }
        'ACTION' { '#A371F7' }
        default  { '#C9D1D9' }
    }
    $rLevel = New-Object System.Windows.Documents.Run("[$Level] ")
    $rLevel.Foreground = $brushConv.ConvertFromString($color)
    $rLevel.FontWeight = [System.Windows.FontWeights]::Bold
    $p.Inlines.Add($rLevel)

    $rMsg = New-Object System.Windows.Documents.Run($Message)
    $rMsg.Foreground = $brushConv.ConvertFromString('#F0F6FC')
    $p.Inlines.Add($rMsg)

    $txtConsole.Document.Blocks.Add($p)
    $txtConsole.ScrollToEnd()
    Invoke-DispatcherUI
}

function Show-ElevationBadge {
    $isAdmin = Test-BTFixAdministrator
    if ($isAdmin) {
        $badgeAdmin.Background = $brushConv.ConvertFromString('#12261E')
        $badgeAdmin.BorderBrush = $brushConv.ConvertFromString('#238636')
        $txtAdmin.Text = '🛡️ Administrator'
        $txtAdmin.Foreground = $brushConv.ConvertFromString('#3FB950')
        $btnElevate.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
        $badgeAdmin.Background = $brushConv.ConvertFromString('#2D2200')
        $badgeAdmin.BorderBrush = $brushConv.ConvertFromString('#9E6A03')
        $txtAdmin.Text = '⚠️ Standard User (Scan Only)'
        $txtAdmin.Foreground = $brushConv.ConvertFromString('#D29922')
        $btnElevate.Visibility = [System.Windows.Visibility]::Visible
    }
}

function Update-HardwareState {
    Write-GuiLog 'INFO' 'Scanning hardware tree for Bluetooth host adapters...'
    $panelRadios.Children.Clear()
    $panelPeripherals.Children.Clear()

    $radios = @(Get-BTFixRadio)
    $txtRadioCount.Text = "$($radios.Count) detected"
    Write-GuiLog 'INFO' "Discovered $($radios.Count) Bluetooth host radio(s)."

    # Superiority assessment
    $superiority = $null
    if ($radios.Count -ge 1) {
        $superiority = Get-BTFixSuperiorRadio -Radios $radios
    }

    foreach ($r in $radios) {
        $border = New-Object System.Windows.Controls.Border
        $border.Background = $brushConv.ConvertFromString('#21262D')
        $border.BorderBrush = $brushConv.ConvertFromString('#30363D')
        $border.BorderThickness = New-Object System.Windows.Thickness(1)
        $border.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $border.Padding = New-Object System.Windows.Thickness(10)
        $border.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

        $sp = New-Object System.Windows.Controls.StackPanel

        # Title row
        $titleGrid = New-Object System.Windows.Controls.Grid
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
        $titleGrid.ColumnDefinitions.Add($col0)
        $titleGrid.ColumnDefinitions.Add($col1)

        $tbName = New-Object System.Windows.Controls.TextBlock
        $tbName.Text = $r.FriendlyName
        $tbName.FontWeight = [System.Windows.FontWeights]::Bold
        $tbName.FontSize = 13
        $tbName.Foreground = $brushConv.ConvertFromString('#F0F6FC')
        [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
        $titleGrid.Children.Add($tbName)

        # Chipset match
        $chipset = @(Get-BTFixChipset -HardwareId ($r.HardwareIds -join ' '))[0]
        if ($chipset -and $chipset.Family -ne 'Unknown chipset') {
            $tbChip = New-Object System.Windows.Controls.TextBlock
            $tbChip.Text = $chipset.Family
            $tbChip.FontSize = 11
            $tbChip.Foreground = $brushConv.ConvertFromString('#8B949E')
            [System.Windows.Controls.Grid]::SetColumn($tbChip, 1)
            $titleGrid.Children.Add($tbChip)
        }
        $sp.Children.Add($titleGrid)

        # Instance ID / Location
        $tbLoc = New-Object System.Windows.Controls.TextBlock
        $tbLoc.Text = $r.InstanceId
        $tbLoc.FontSize = 10
        $tbLoc.Foreground = $brushConv.ConvertFromString('#6E7681')
        $tbLoc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 6)
        $tbLoc.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $sp.Children.Add($tbLoc)

        # Badges WrapPanel
        $wp = New-Object System.Windows.Controls.WrapPanel

        # Badge 1: Placement
        $bPlace = New-Object System.Windows.Controls.Border
        $bPlace.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $bPlace.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        $bPlace.Margin = New-Object System.Windows.Thickness(0, 0, 6, 4)
        $tbPlace = New-Object System.Windows.Controls.TextBlock
        $tbPlace.FontSize = 11
        if ($r.IsInternal) {
            $bPlace.Background = $brushConv.ConvertFromString('#161B22')
            $tbPlace.Text = 'Motherboard Internal'
            $tbPlace.Foreground = $brushConv.ConvertFromString('#8B949E')
        } else {
            $bPlace.Background = $brushConv.ConvertFromString('#1F2D3D')
            $tbPlace.Text = 'External USB Dongle'
            $tbPlace.Foreground = $brushConv.ConvertFromString('#58A6FF')
        }
        $bPlace.Child = $tbPlace
        $wp.Children.Add($bPlace)

        # Badge 2: Bluetooth LMP Spec
        $bLmp = New-Object System.Windows.Controls.Border
        $bLmp.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $bLmp.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        $bLmp.Margin = New-Object System.Windows.Thickness(0, 0, 6, 4)
        $bLmp.Background = $brushConv.ConvertFromString('#261C3B')
        $tbLmp = New-Object System.Windows.Controls.TextBlock
        $tbLmp.FontSize = 11
        $tbLmp.Foreground = $brushConv.ConvertFromString('#BC8CFF')
        if ($r.LmpVersion) {
            $tbLmp.Text = "$(Get-BTFixLmpVersionName $r.LmpVersion) (LMP $($r.LmpVersion))"
        } else {
            $tbLmp.Text = 'LMP: Unknown / Blocked'
        }
        $bLmp.Child = $tbLmp
        $wp.Children.Add($bLmp)

        # Badge 3: Hardware Status
        $bStatus = New-Object System.Windows.Controls.Border
        $bStatus.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $bStatus.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        $bStatus.Margin = New-Object System.Windows.Thickness(0, 0, 6, 4)
        $tbStatus = New-Object System.Windows.Controls.TextBlock
        $tbStatus.FontSize = 11
        $tbStatus.FontWeight = [System.Windows.FontWeights]::SemiBold
        if ($r.IsHealthy) {
            $bStatus.Background = $brushConv.ConvertFromString('#12261E')
            $tbStatus.Text = '🟢 Active (Code 0)'
            $tbStatus.Foreground = $brushConv.ConvertFromString('#3FB950')
        } elseif ($r.IsDisabled) {
            $bStatus.Background = $brushConv.ConvertFromString('#2D2200')
            $tbStatus.Text = '🟡 Parked (Code 22)'
            $tbStatus.Foreground = $brushConv.ConvertFromString('#D29922')
        } elseif ($r.ProblemCode -eq 31) {
            $bStatus.Background = $brushConv.ConvertFromString('#361214')
            $tbStatus.Text = '🔴 Conflict (Code 31)'
            $tbStatus.Foreground = $brushConv.ConvertFromString('#F85149')
        } else {
            $bStatus.Background = $brushConv.ConvertFromString('#361214')
            $tbStatus.Text = "⚠️ Error (Code $($r.ProblemCode))"
            $tbStatus.Foreground = $brushConv.ConvertFromString('#F85149')
        }
        $bStatus.Child = $tbStatus
        $wp.Children.Add($bStatus)

        # Badge 4: Superiority Score
        if ($superiority) {
            $scoreObj = @($superiority.Rankings | Where-Object { $_.Radio.InstanceId -eq $r.InstanceId })[0]
            if ($scoreObj) {
                $bScore = New-Object System.Windows.Controls.Border
                $bScore.CornerRadius = New-Object System.Windows.CornerRadius(4)
                $bScore.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
                $bScore.Margin = New-Object System.Windows.Thickness(0, 0, 6, 4)
                $tbScore = New-Object System.Windows.Controls.TextBlock
                $tbScore.FontSize = 11
                $tbScore.FontWeight = [System.Windows.FontWeights]::SemiBold
                if ($superiority.SuperiorRadio.InstanceId -eq $r.InstanceId) {
                    $bScore.Background = $brushConv.ConvertFromString('#1F3B2B')
                    $tbScore.Text = "Score: $($scoreObj.Score)/100 🏆 Superior"
                    $tbScore.Foreground = $brushConv.ConvertFromString('#3FB950')
                    $border.BorderBrush = $brushConv.ConvertFromString('#2EA043')
                } else {
                    $bScore.Background = $brushConv.ConvertFromString('#161B22')
                    $tbScore.Text = "Score: $($scoreObj.Score)/100"
                    $tbScore.Foreground = $brushConv.ConvertFromString('#8B949E')
                }
                $bScore.Child = $tbScore
                $wp.Children.Add($bScore)
            }
        }

        $sp.Children.Add($wp)
        $border.Child = $sp
        $panelRadios.Children.Add($border)
    }

    # Peripherals
    Write-GuiLog 'INFO' 'Enumerating paired Bluetooth audio endpoints...'
    $peripherals = @(Get-BTFixPairedDevice)
    $txtPeripheralCount.Text = "$($peripherals.Count) found"
    if ($peripherals.Count -eq 0) {
        $tbNone = New-Object System.Windows.Controls.TextBlock
        $tbNone.Text = 'No paired Bluetooth peripherals found.'
        $tbNone.Foreground = $brushConv.ConvertFromString('#6E7681')
        $tbNone.FontSize = 12
        $panelPeripherals.Children.Add($tbNone)
    } else {
        foreach ($p in $peripherals) {
            $bPer = New-Object System.Windows.Controls.Border
            $bPer.Background = $brushConv.ConvertFromString('#21262D')
            $bPer.BorderBrush = $brushConv.ConvertFromString('#30363D')
            $bPer.BorderThickness = New-Object System.Windows.Thickness(1)
            $bPer.CornerRadius = New-Object System.Windows.CornerRadius(6)
            $bPer.Padding = New-Object System.Windows.Thickness(8)
            $bPer.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

            $dp = New-Object System.Windows.Controls.DockPanel
            $tbPName = New-Object System.Windows.Controls.TextBlock
            $tbPName.Text = $p.FriendlyName
            $tbPName.FontSize = 12
            $tbPName.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbPName.Foreground = $brushConv.ConvertFromString('#F0F6FC')
            $dp.Children.Add($tbPName)

            $tbPStatus = New-Object System.Windows.Controls.TextBlock
            $tbPStatus.FontSize = 11
            $tbPStatus.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
            if ($p.IsConnected) {
                $tbPStatus.Text = '🟢 Connected'
                $tbPStatus.Foreground = $brushConv.ConvertFromString('#3FB950')
            } elseif ($p.IsNotPresent) {
                $tbPStatus.Text = '⚪ Paired (Standby)'
                $tbPStatus.Foreground = $brushConv.ConvertFromString('#8B949E')
            } else {
                $tbPStatus.Text = "Code $($p.ProblemCode)"
                $tbPStatus.Foreground = $brushConv.ConvertFromString('#D29922')
            }
            $dp.Children.Add($tbPStatus)
            $bPer.Child = $dp
            $panelPeripherals.Children.Add($bPer)
        }
    }

    # Diagnosis Analysis
    $diag = Get-BTFixDiagnosis -Inventory $radios -NoLive
    $findings = @(Get-BTFixFinding -Inventory $radios -NoLive)

    if ($diag.Classification -eq 'RadioConflictOrDriverStartFailure') {
        $borderDiagnosis.Background = $brushConv.ConvertFromString('#361214')
        $borderDiagnosis.BorderBrush = $brushConv.ConvertFromString('#F85149')
        $txtDiagnosisIcon.Text = '🔴'
        $txtDiagnosisTitle.Text = 'CRITICAL: Dual-Radio Conflict Detected'
        $txtDiagnosisTitle.Foreground = $brushConv.ConvertFromString('#F85149')
        $txtDiagnosisDetail.Text = 'Windows is locking the internal adapter and blocking your USB dongle with Code 31. Click Auto-Fix to isolate and activate the superior radio.'
        Write-GuiLog 'WARN' 'Dual-radio conflict detected! An adapter is blocked in Code 31.'
    } elseif ($diag.Classification -eq 'HealthyWithDisabledRadio') {
        $borderDiagnosis.Background = $brushConv.ConvertFromString('#12261E')
        $borderDiagnosis.BorderBrush = $brushConv.ConvertFromString('#2EA043')
        $txtDiagnosisIcon.Text = '🟢'
        $txtDiagnosisTitle.Text = 'System Healthy & Conflict-Free'
        $txtDiagnosisTitle.Foreground = $brushConv.ConvertFromString('#3FB950')
        $txtDiagnosisDetail.Text = 'Primary radio is active and healthy; the competing adapter is safely parked.'
        Write-GuiLog 'OK' 'Stack is healthy: primary radio active, secondary adapter parked.'
    } elseif ($diag.Classification -eq 'Healthy') {
        $borderDiagnosis.Background = $brushConv.ConvertFromString('#12261E')
        $borderDiagnosis.BorderBrush = $brushConv.ConvertFromString('#2EA043')
        $txtDiagnosisIcon.Text = '🟢'
        $txtDiagnosisTitle.Text = 'Bluetooth Stack Healthy'
        $txtDiagnosisTitle.Foreground = $brushConv.ConvertFromString('#3FB950')
        $txtDiagnosisDetail.Text = 'Single active radio operating normally with zero hardware conflicts.'
        Write-GuiLog 'OK' 'Bluetooth stack operating normally.'
    } elseif ($diag.Classification -eq 'AllRadiosDisabled' -or $diag.Classification -eq 'SingleRadioDisabled') {
        $borderDiagnosis.Background = $brushConv.ConvertFromString('#2D2200')
        $borderDiagnosis.BorderBrush = $brushConv.ConvertFromString('#D29922')
        $txtDiagnosisIcon.Text = '🟡'
        $txtDiagnosisTitle.Text = 'Bluetooth Adapter Disabled (Code 22)'
        $txtDiagnosisTitle.Foreground = $brushConv.ConvertFromString('#D29922')
        $txtDiagnosisDetail.Text = 'No active Bluetooth radio available. Click Auto-Fix to re-enable your adapter.'
        Write-GuiLog 'WARN' 'Bluetooth adapter is currently disabled.'
    } else {
        $borderDiagnosis.Background = $brushConv.ConvertFromString('#21262D')
        $borderDiagnosis.BorderBrush = $brushConv.ConvertFromString('#30363D')
        $txtDiagnosisIcon.Text = 'ℹ️'
        $txtDiagnosisTitle.Text = "Diagnosis: $($diag.Classification)"
        $txtDiagnosisTitle.Foreground = $brushConv.ConvertFromString('#F0F6FC')
        $txtDiagnosisDetail.Text = ($diag.RecommendedActions -join ' | ')
        Write-GuiLog 'INFO' "Diagnosis: $($diag.Classification)"
    }
}

# ----------------- Event Handlers -----------------

$btnElevate.Add_Click({
    $script = $MyInvocation.MyCommand.Path
    if (-not $script) { $script = Join-Path $scriptRoot 'BTFix-GUI.ps1' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"")
        $window.Close()
    } catch {
        Write-GuiLog 'ERROR' "Failed to request administrator elevation: $($_.Exception.Message)"
    }
})

$btnScan.Add_Click({
    Update-HardwareState
})

$btnClearLog.Add_Click({
    $txtConsole.Document.Blocks.Clear()
})

$btnAutoFix.Add_Click({
    if (-not (Test-BTFixAdministrator)) {
        [System.Windows.MessageBox]::Show('Administrator rights are required to repair Bluetooth hardware devices and restart system services.', 'Administrator Elevation Required', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        $btnElevate.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        return
    }

    $btnAutoFix.IsEnabled = $false
    $btnScan.IsEnabled = $false
    $btnRestartAudio.IsEnabled = $false
    $btnRollback.IsEnabled = $false

    try {
        Write-GuiLog 'ACTION' 'Beginning automated Bluetooth repair sequence...'
        $params = @{}
        if ($chkPreferInternal.IsChecked) { $params['PreferInternal'] = $true }
        if ($chkDisableUsbSuspend.IsChecked) { $params['DisableUsbSuspend'] = $true }

        $res = Invoke-BTFixRepair @params
        Write-GuiLog 'OK' "Repair pipeline finished: $($res.Count) change(s) recorded."
        
        # Immediate state reload
        Update-HardwareState
    } catch {
        Write-GuiLog 'ERROR' "Repair encountered an error: $($_.Exception.Message)"
    } finally {
        $btnAutoFix.IsEnabled = $true
        $btnScan.IsEnabled = $true
        $btnRestartAudio.IsEnabled = $true
        $btnRollback.IsEnabled = $true
    }
})

$btnRestartAudio.Add_Click({
    if (-not (Test-BTFixAdministrator)) {
        [System.Windows.MessageBox]::Show('Administrator rights are required to restart Windows Audio Endpoint Builder and BTAGService.', 'Administrator Required', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    try {
        Write-GuiLog 'ACTION' 'Restarting BTAGService and Windows AudioEndpointBuilder...'
        Restart-BTFixAudioStack
        Write-GuiLog 'OK' 'Audio services successfully cycled. Output endpoints re-registered.'
        Update-HardwareState
    } catch {
        Write-GuiLog 'ERROR' "Failed cycling audio services: $($_.Exception.Message)"
    }
})

$btnRollback.Add_Click({
    if (-not (Test-BTFixAdministrator)) {
        [System.Windows.MessageBox]::Show('Administrator rights are required to rollback hardware configurations.', 'Administrator Required', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    try {
        Write-GuiLog 'ACTION' 'Restoring hardware state from latest backup snapshot...'
        $restored = Invoke-BTFixRollback
        if ($restored) {
            Write-GuiLog 'OK' "Rollback applied to $($restored.Count) radio(s)."
        } else {
            Write-GuiLog 'WARN' 'No previous snapshot found or no changes needed restoring.'
        }
        Update-HardwareState
    } catch {
        Write-GuiLog 'ERROR' "Rollback failed: $($_.Exception.Message)"
    }
})

$btnExport.Add_Click({
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $reportFile = Join-Path $desktop ("BTFix-Report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".md")
        Write-BTFixReport -OutputPath $reportFile
        Write-GuiLog 'OK' "Full diagnostics bundle saved to: $reportFile"
        [System.Windows.MessageBox]::Show("Diagnostics report successfully saved to:`n$reportFile", 'Report Exported', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } catch {
        Write-GuiLog 'ERROR' "Failed to export report: $($_.Exception.Message)"
    }
})

# Initialize UI
Show-ElevationBadge
Update-HardwareState

$window.ShowDialog() | Out-Null
