# Bluetooth Dongle Fix

Diagnose and repair USB Bluetooth adapters (dongles) that Windows refuses to
start — the classic **Code 31 (CM_PROB_FAILED_ADD)** with a "Generic Bluetooth
Radio" entry and a yellow exclamation mark in Device Manager.

Most guides tell you to "download a driver". That is usually wrong: for
chipset clones (CSR / Cambridge Silicon Radio and the many rebrands of it)
Windows Update has **no** driver at all, and the generic `bth.inf` driver is
the correct one. The real cause is nearly always a **radio conflict**: the
internal adapter and the dongle cannot both hold the Bluetooth stack.

This tool finds the real cause and fixes it — reversibly.

## What it checks

| Check | What it looks at |
| --- | --- |
| Radio inventory | every Bluetooth radio, its driver, problem code, and whether it is on-board or a dongle (via the device *container id*) |
| Dual-radio conflict | one adapter owning the stack while the other fails with code 31 |
| Problem codes | the full Microsoft `CM_PROB_*` table (code 31, 28, 48, 45, 10, 43, 22, …) with the official wording and a fix for each |
| Services | `bthserv`, `DeviceAssociationService`, `DeviceInstall` |
| Software radio switch | Windows can have Bluetooth switched off machine-wide, which looks exactly like a broken dongle |
| Paired peripherals | devices paired but "not connected" (code 45) — the reason earbuds refuse to come back |
| USB power | selective suspend on a dongle, which makes it disappear after a few idle minutes |
| Chipset guidance | known USB ids (CSR, Realtek, Intel, Qualcomm, MediaTek, Broadcom) with where to get a working driver |

## Quick start

### Double-Click Launchers (No CLI Needed)
* **`BTFix.bat`**: Interactive text menu (Check, Fix, Rollback, Forget device, Compare Radios).
* **`Run-Fix-As-Admin.bat`**: One-click auto-elevating repair shortcut.

### PowerShell CLI
```powershell
# 1. see what is wrong (safe, read-only)
.\BTFix.ps1

# 2. benchmark & compare all radios to find which is superior
.\BTFix.ps1 -Mode Compare

# 3. fix conflict (auto-detects superior radio and parks the conflicting one)
.\BTFix.ps1 -Mode Fix

# 4. not what you wanted? go back
.\BTFix.ps1 -Mode Rollback
```

## Modes

| Mode | What happens | Needs admin |
| --- | --- | --- |
| `Check` (default) | Runs every check and prints prioritized findings: what is wrong, why it matters, how to fix it, and whether BTFix can fix it itself. **Read-only.** | no |
| `Compare` | Evaluates LMP specs (Bluetooth 4.0 to 6.0), antenna placement, RF clearance, and hardware reliability, scoring and ranking all radios out of 100. | no |
| `Fix` | Snapshots the state, auto-selects the superior radio, and applies repairs. | yes |
| `Rollback` | Restores the state saved by the last `Fix` (re-enables the radios it disabled). | yes |
| `Forget` | Forgets a paired peripheral so it can be paired again. | yes |
| `Chipsets` | Prints the chipset/driver guidance table. | no |
| `Report` | Writes a Markdown + JSON diagnostics bundle for a bug report. | no |

## Superiority Benchmark Engine

Windows does not support running multiple active Bluetooth host radios simultaneously. When an external dongle is plugged in alongside an internal motherboard adapter, Windows locks onto one and blocks the second with Code 31.

BTFix's **Superiority Engine** eliminates guesswork:
* **LMP Version Inspection**: Queries `DEVPKEY_Bluetooth_RadioLmpVersion` and HCI properties to map the exact Bluetooth spec (from Bluetooth 4.0 up to Bluetooth 5.4 / 6.0).
* **RF Environment & Antenna Clearance**: Scores external USB dongles higher because dedicated antennas outside the laptop chassis avoid internal Wi-Fi 2.4GHz coexistence time-slicing and metal Faraday cage shielding.
* **Auto-Selection**: In `-Mode Fix`, BTFix automatically prioritizes and activates the superior radio unless overridden by `-Radio` or `-PreferInternal`.

## The repair pipeline

1. **Snapshot** the radio state into `%LOCALAPPDATA%\BTFix\backups\<timestamp>.json`.
2. **Start the services** the stack needs (`bthserv` and friends).
3. **Restart** `bthserv` so the stack releases the radios.
4. **Re-enumerate** the broken radio: remove the device node and re-scan.
5. **Break the conflict** — *only if the radio you want working is the broken
   one*: the other radio is parked so the wanted one can take the stack.
   The wanted radio is, in order: the one you name with `-Radio`, otherwise the
   external dongle, otherwise the internal adapter.
6. **Re-enable** the wanted radio if it was merely disabled.
7. **Optional extras**: `-DisableUsbSuspend` (stop Windows powering the dongle
   down), `-ForgetStale` (drop peripherals that are paired but not connected).
8. **Verify** that every radio ends up `Status = OK` with problem code 0.

Every step is logged to `%LOCALAPPDATA%\BTFix\logs\`.

## Options

| Option | Meaning |
| --- | --- |
| `-Mode` | `Check`, `Fix`, `Rollback`, `Forget`, `Chipsets`, `Report` |
| `-Radio <instanceId>` | Which radio you want working (default: the external dongle) |
| `-Device <name>` | Paired device to forget (name fragment or instance id) |
| `-PreferInternal` | Prefer the built-in adapter over the dongle |
| `-SearchWindowsUpdate` | Also query Windows Update for an optional driver (slow) |
| `-DisableUsbSuspend` | Stop Windows from powering the dongle down |
| `-ForgetStale` | Forget peripherals that are paired but not connected |
| `-NoElevation` | Fail instead of asking for elevation |
| `-BackupPath <dir>` | Where snapshots are stored (default `%LOCALAPPDATA%\BTFix\backups`) |
| `-ReportPath <file>` | Where the Markdown report is written |
| `-WhatIf` | Show the plan without changing anything |

## Requirements

- Windows 10 1809 or newer (tested on Windows 11 24H2, PowerShell 5.1 and 7.x)
- Administrator rights for `Fix` / `Rollback` / `Forget` (the tool elevates itself)
- No extra modules required

## Safety

* `Check` never writes to the system.
* `Fix` always snapshots first, and `Rollback` restores it.
* Only devices in the **Bluetooth** class are touched; Wi-Fi, USB and HID
  devices are never modified.
* Nothing is downloaded or installed unless you pass `-SearchWindowsUpdate`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — including how to add a new chipset
profile and how to run the test suite.

## License

MIT — see [LICENSE](LICENSE).
