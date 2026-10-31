# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.1.0] - 2026-10-31

### Added
- **Bluetooth LE Audio, LC3 Codec & Auracast Broadcast Manager (`-Mode LEAudio`)**:
  - Full capability detection across Windows 11 22H2 (build 22621+ unicast LC3) and 24H2 (build 26100+ Auracast).
  - Inspects Bluetooth Core 5.2+ Isochronous Channels (`LMP >= 11`) and Bluetooth 5.3+ broadcast hardware (`LMP >= 12`).
  - Manages `HKLM:\SYSTEM\CurrentControlSet\Services\BthAvctpSvc\Parameters\Bats\UserPrefersClassicAudio` policy (`-State Enable`, `-State Disable`, `-State Default`).
  - Automated JSON rollback snapshots under `%LOCALAPPDATA%\BTFix\leaudio-backups`.
  - Added native `⚡ LE Audio & LC3` action button in GUI with live log streaming.
- **Anti-HandsFree Telephony Hi-Fi Enforcer (`-Mode HandsFree`)**:
  - Permanently isolates virtual Hands-Free Profile (HFP/HSP) telephony nodes while maintaining pristine 44.1/48kHz A2DP stereo playback during voice calls.
- **Bluetooth LE & Audio Battery Percentage Inspector (`-Mode Battery`)**:
  - Directly queries `DEVPKEY_Device_BatteryPercentage` across connected GATT and classic audio peripherals.
  - Visual terminal ASCII battery bars and dynamic color badges in GUI.
- **High-Bitrate A2DP Codec Optimizer (`-Mode Codec`)**:
  - Enforces native AAC and aptX codecs and disables erratic AVRCP Absolute Volume jumps.
- **Esports Low-Latency Controller Mode (`-Mode GameMode`)**:
  - Automatically identifies PS5 DualSense, Xbox Wireless, and Switch Pro gamepads, disabling USB selective suspend and power throttling for lowest input latency.
- **Automated Diagnostic Findings Engine**:
  - Added `leaudio-disabled-by-policy` finding alerting users when LE Audio hardware is suppressed by Windows policy.
- **USB 3.0 / SuperSpeed RF Interference & Port Topology Inspector (`-Mode Topology`)**:
  - Traverses PnP device hierarchy (`DEVPKEY_Device_Parent`) to map host controllers (xHCI/EHCI), root hubs (`ROOT_HUB30` vs `ROOT_HUB20`), and intermediate tiers.
  - Identifies physical USB 3.0/3.1 SuperSpeed ports whose spread-spectrum clock harmonics directly radiate 2.4–2.5 GHz noise into the Bluetooth band (Intel White Paper #327216-001).
  - Detects concurrent `USBSTOR*` high-bandwidth storage traffic on the controller tree raising the noise floor by 15–20 dB.
  - Emits multi-tier risk evaluations (`Low`, `Medium`, `High`) with actionable physical mitigations (USB 2.0 ports or shielded extension cables >= 1m).
  - Displays dynamic RF badges in GUI (`BTFix-GUI.ps1`) and alerts via diagnostic findings (`usb3-rf-interference-*`).

### Performance & Reliability
- **PnP Batch Property Retrieval**: Switched from N individual WMI queries to single-pass batch property queries, speeding up scan times from ~4s to ~350ms.
- **O(1) Problem Code Dictionary**: Replaced linear pipeline searches with constant-time hashtable lookups.
- **Non-blocking GUI Self-Test**: Added non-blocking self-test exit for CI headless validation.
- **Expanded Test Suite**: 80 unit tests with 100% pass rate in Windows PowerShell 5.1 and PS 7+, and 0 PSScriptAnalyzer warnings.

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
