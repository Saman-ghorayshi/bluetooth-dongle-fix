# Bluetooth Dongle Fix

Diagnose and repair USB Bluetooth adapters (dongles) that Windows refuses to
start on Windows 10/11 — the classic **Code 31 (CM_PROB_FAILED_ADD)** with
`0xC0000001` and a "Generic Bluetooth Radio" entry.

Most guides tell you to "download a driver". That is usually wrong: for
chipset clones (CSR / Cambridge Silicon Radio, and other rebadged VID:PID
pairs) Windows Update has **no** driver at all, and the generic `bth.inf`
driver is the correct one. The real cause is usually a **radio conflict**:
the internal adapter and the dongle cannot both hold the Bluetooth stack.

This tool finds the real cause and fixes it — reversibly.

## What it does

| Mode | What happens | Needs admin |
| --- | --- | --- |
| `Diagnose` (default) | Inventories every Bluetooth radio, driver, problem code and service; prints the likely cause and a recommended plan. **Read-only.** | no |
| `Repair` | Runs the repair pipeline: snapshot → restart the Bluetooth stack → re-enumerate the broken radio → break a dual-radio conflict (disable the other radio) → re-verify. | yes |
| `Rollback` | Restores the exact device state saved by the last `Repair` (re-enables radios that were disabled, re-adds removed ones). | yes |
| `Report` | Writes a Markdown + JSON diagnostics bundle for a bug report. | no |

## Quick start

```powershell
# 1. see what is wrong (safe, read-only)
.\BTFix.ps1

# 2. fix it (prompts for elevation)
.\BTFix.ps1 -Mode Repair

# 3. not what you wanted? go back
.\BTFix.ps1 -Mode Rollback
```

## The repair pipeline

1. **Snapshot** every radio's state (present / disabled / problem code / driver)
   into `%LOCALAPPDATA%\BTFix\backups\<timestamp>.json`.
2. **Restart** `bthserv` so the stack releases the radio.
3. **Re-enumerate** the broken radio: remove the device node and re-scan
   (`pnputil /scan-devices`). A surprising number of Code 31 cases clear here.
4. **Break the conflict**: if the radio is still Code 31 *and* another radio is
   healthy, disable the healthy one and re-scan. The stack can only be held by
   one radio, so the dongle now comes up cleanly.
5. **Verify**: the radio must reach `Status = OK` with problem code 0.
6. **Report** what changed, and where the backup lives for a rollback.

Every step is logged to `%LOCALAPPDATA%\BTFix\logs\`.

## Options

| Option | Meaning |
| --- | --- |
| `-Mode` | `Diagnose`, `Repair`, `Rollback`, `Report` |
| `-Radio <instanceId>` | Only consider this radio (default: all) |
| `-PreferInternal` | When breaking a conflict, keep the *internal* adapter and disable the dongle (default: keep the dongle, which is usually the one the user just bought) |
| `-SearchWindowsUpdate` | Also query Windows Update for an optional driver (slow, needs network) |
| `-NoElevation` | Fail instead of asking for elevation |
| `-BackupPath <dir>` | Where to store snapshots (default `%LOCALAPPDATA%\BTFix\backups`) |
| `-WhatIf` | Show the plan without changing anything |

## Requirements

- Windows 10 1809 or newer (tested on Windows 11 24H2, PowerShell 5.1 and 7.x)
- Administrator rights for `Repair` / `Rollback` (the tool elevates itself)
- No extra modules required

## Safety

* `Diagnose` never writes to the system.
* `Repair` always snapshots first, and `Rollback` restores it.
* Only Bluetooth-class radios are touched; Wi-Fi, USB and other devices are
  never modified.
* Nothing is downloaded or installed unless you pass `-SearchWindowsUpdate`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — including how to add a new chipset
profile and how to run the test suite.

## License

MIT — see [LICENSE](LICENSE).
