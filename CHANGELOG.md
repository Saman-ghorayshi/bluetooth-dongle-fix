# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-27

### Fixed
- The repair could pick the wrong radio in the exact scenario the tool
  exists for: a Code 31 dongle never started, so Windows had no LMP data
  for it and it scored a 30-point baseline, losing to any healthy internal
  card with a readable LMP. Selection is now conflict-aware and shared by
  both repair passes (`Resolve-BTFixWantedRadio`); the Superiority Engine
  only ranks radios it can actually benchmark.
- `-DisableUsbSuspend` wrote `EnhancedPowerManagementEnabled` into the USB
  *hub's* registry key instead of the dongle's own (Microsoft KB 2900614),
  making the feature a no-op. It now targets the device's own key, and the
  original value is snapshotted and restored by rollback.
- GUI: the superiority score badge never rendered (`.Rankings` vs
  `.Scores`) and the LMP badge always read "Unknown" (radios carry no LMP
  property). Both fixed and covered by a new `-SelfTest` smoke test.
- GUI: result messages used `.Count` on result objects (always blank) and
  never reported a required reboot.
- `DEVPKEY_Device_ProblemProvider` does not exist; the driver column in
  reports was always empty (now `DEVPKEY_Device_DriverProvider`).
- Bluetooth 4.1 scored below Bluetooth 4.0 (LMP 7 fell into the `lmp*3`
  fallback).
- `BTFix.bat` split its window title at the unescaped `&`.
- Every unchecked `UIElementCollection.Add` in the GUI leaked the insertion
  index to the console.
- The steps log no longer claims "restarted bthserv" when the restart was
  skipped.

### Added
- Radios on PCI/SDIO/ACPI/UART buses are now enumerated (previously only
  `USB\*` nodes); peripherals stay excluded.
- Reboot detection is locale-independent (pnputil exit code 3010 and
  problem code 14, with the English text as a last resort).
- GUI repair runs in a background process: the window no longer freezes,
  and repairs leave persistent logs.
- `-Mode Report` writes a JSON twin next to the Markdown report.
- Snapshot includes the USB power-management state; rollback restores it.
- Installer: TLS 1.2 enforced, aborts when core files fail to download,
  uninstall keeps snapshots and logs.

## [1.0.0] - 2026-10-21

### Added
- `BTFix.ps1` CLI with `Diagnose`, `Repair`, `Rollback` and `Report` modes.
- Self-elevation with argument forwarding; `-NoElevation` to opt out.
- Dual-radio conflict detection and resolution (the "Generic Bluetooth Radio
  fails with Code 31" case).
- JSON snapshots in `%LOCALAPPDATA%\BTFix\backups` and a rollback that
  re-enables exactly what a repair disabled.
- Optional Windows Update driver search (`-SearchWindowsUpdate`).
- Markdown diagnostics report for bug reports.
- Dependency-free test suite (14 tests) and GitHub Actions CI
  (Windows PowerShell 5.1 + PSScriptAnalyzer).
