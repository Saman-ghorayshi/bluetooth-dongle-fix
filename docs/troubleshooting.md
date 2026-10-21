# Troubleshooting: Bluetooth dongles that "do not work"

This guide is the manual behind `BTFix`. It explains what the problem codes
mean and what actually fixes them.

## The most common situation

You bought a USB Bluetooth dongle. Windows 10/11 shows it in Device Manager
as **"Generic Bluetooth Radio"** with a yellow exclamation mark, and your
headphones still do not connect. Meanwhile the laptop's built-in adapter works
fine.

### What is really going on

1. The dongle is a rebadged chipset (very often CSR / Cambridge Silicon
   Radio, sold under dozens of brand names). Its USB ID is something like
   `USB\VID_0A12&PID_0001`.
2. Windows has **no vendor driver** for it — `pnputil /enum-devices` will
   happily show "Matching Device ID: USB\VID_0A12&PID_0001", but the only
   driver that matches is Microsoft's generic `bth.inf`.
3. The generic driver **is** the right driver. The problem is that it cannot
   start while another radio holds the Bluetooth stack: Windows lets one
   adapter own the stack, and a second one fails with
   **Code 31 (CM_PROB_FAILED_ADD)**, status `0xC0000001`.

So "install a driver" is the wrong advice. The fix is to make sure the stack
is held by the radio you actually want to use.

### The fix

```powershell
.\BTFix.ps1 -Mode Repair
```

which does the equivalent of:

```powershell
# 1. find the radios
pnputil /enum-devices /class Bluetooth

# 2. free the stack: disable the radio that currently owns it
pnputil /disable-device "USB\VID_0BDA&PID_4853\00E04C000001"

# 3. re-enumerate the dongle so it grabs the stack
pnputil /remove-device "USB\VID_0A12&PID_0001\5&5E7D000&0&3"
pnputil /scan-devices
```

After this the dongle reports `Status: OK` and your devices pair normally.

### Which radio should win?

* **The dongle** (default): better antenna, no interference with the Wi-Fi
  antenna, works even if the internal one is muted.
* **The internal adapter**: fewer moving parts, and its vendor driver is
  usually better tuned for the laptop's antenna.

Choose with `-PreferInternal`:

```powershell
.\BTFix.ps1 -Mode Repair -PreferInternal
```

### Undo

```powershell
.\BTFix.ps1 -Mode Rollback
```

re-enables whatever the last repair disabled (snapshots live in
`%LOCALAPPDATA%\BTFix\backups`).

## Problem codes

| Code | Meaning | What to do |
| --- | --- | --- |
| **31** | `CM_PROB_FAILED_ADD` — the driver loaded but the device failed to start. Almost always a **radio conflict** on Bluetooth dongles. | Disable the other radio, rescan. `.\BTFix.ps1 -Mode Repair` |
| **28** | No driver installed for this hardware ID. | `.\BTFix.ps1 -Mode Repair -SearchWindowsUpdate`, or get the vendor's driver (CSR / Realtek / MediaTek depending on chipset). |
| **10** | `CM_PROB_FAILED_START` — the device cannot be started. | Move it to a USB 2.0 port, then remove + rescan. |
| **22** | `CM_PROB_DISABLED` — **the device is disabled**. This is not an error; it is how a parked radio looks. | Re-enable with `pnputil /enable-device "<id>"` or `.\BTFix.ps1 -Mode Rollback`. |
| **43** | The device was removed / is not present. | Plug it in again, or re-pair the device. |

## Other things worth checking

* **USB port** — a USB 3.x port can fail to enumerate some of the older
  CSR dongles. Try a USB 2.0 port.
* **USB power management** — Windows may power down the dongle. In Device
  Manager, *Properties → Power Management*, untick "Allow the computer to turn
  off this device to save power".
* **Bluetooth support service** — must be running:
  `Get-Service bthserv` (BTFix restarts it during a repair).
* **Two radios** — if the dongle works only while the internal adapter is
  disabled, some devices (AirPods, some fitness bands) will bind to whichever
  radio is active. Pick one and keep it.
* **Driver store leftovers** — a previously installed vendor driver can keep
  failing after an update. `pnputil /remove-device` (not just uninstall) is
  the reliable way to clear it.

## Collecting a report for a bug

```powershell
.\BTFix.ps1 -Mode Report
```

writes a Markdown file (and prints it) containing every radio, its problem
code, the driver in use, the service states and the tool's classification.
Attach it to an issue — it removes an entire round of questions.

## Supported platforms

* Windows 10 1809+, Windows 11 (tested on 24H2)
* Windows PowerShell 5.1 and PowerShell 7+
* x64 and ARM64
* Administrator rights only for `Repair` / `Rollback`
