# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-10-27

### Security
- **Integrity verification before every run.** The suite installs into a
  user-writable folder but self-elevates, so malware with user rights could
  swap the scripts and wait for an elevated run. Every start now checks the
  SHA256 of the code files: the authoritative baseline lives in HKLM
  (recorded by the first elevated run), the installer's `file-hashes.json`
  is the advisory fallback, and a mismatch refuses to run (exit 3).
- **Tag-pinned releases.** `-Version vX.Y.Z` pins the installer to a release
  and verifies every downloaded file against the release's own manifest;
  GitHub Releases ship the zip plus `SHA256SUMS.txt`.

### Fixed
- An explicit `-Radio` that matched nothing silently fell through to the
  default selection, so `Fix -Radio <typo>` could disable a radio the user
  did not point at. It is now a hard error (exit 2) in the CLI, and the
  repair core refuses to guess.
- **The PnP safety guard was decorative**: its `throw` sat inside its own
  `try/catch`, which swallowed it and ran the mutation anyway. A
  non-Bluetooth target is now a real hard stop (caught by the new guard
  test).

### Added
- A repair mutex: a second concurrent repair/rollback (GUI child plus CLI)
  fails fast with exit 2 instead of interleaving pnputil calls.
- `pnputil` indirection point plus mocked end-to-end pipeline tests: the
  conflict repair sequence, `-PreferInternal` behavior, the safety guard,
  and reboot flagging all run without touching hardware.

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
