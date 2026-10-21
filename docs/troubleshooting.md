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
2. Windows has **no vendor driver** for it. `pnputil /enum-devices` shows
   "Matching Device ID: USB\VID_0A12&PID_0001", but the only driver that
   matches is Microsoft's generic `bth.inf`.
3. The generic driver **is** the right driver. The problem is that it cannot
   start while another radio holds the Bluetooth stack: Windows lets one
   adapter own the stack, and a second one fails with
   **Code 31 (CM_PROB_FAILED_ADD)**, status `0xC0000001`.

So "install a driver" is the wrong advice. The fix is to make sure the stack
is held by the radio you actually want to use.

### The fix

```powershell
.\BTFix.ps1 -Mode Fix
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
.\BTFix.ps1 -Mode Fix -PreferInternal
```

### Undo

```powershell
.\BTFix.ps1 -Mode Rollback
```

re-enables whatever the last fix disabled (snapshots live in
`%LOCALAPPDATA%\BTFix\backups`).

## Problem codes

The names and meanings are Microsoft's (`CM_PROB_*`); the fixes are what
works in practice.

| Code | Name | What it means | What to do |
| --- | --- | --- | --- |
| **31** | `CM_PROB_FAILED_ADD` | "Windows cannot load the drivers required for this device." On dongles this is nearly always a **radio conflict**. | Disable the other radio and re-scan. `.\BTFix.ps1 -Mode Fix` |
| **28** | `CM_PROB_FAILED_INSTALL` | "The drivers for this device are not installed" (status `0xC0000490` = DNF, no compatible driver). | Install the vendor driver for the hardware id, or `-SearchWindowsUpdate`. |
| **48** | `CM_PROB_DRIVER_BLOCKED` | The driver is blocked by Windows Driver Protection / Memory Integrity. | Get a newer driver from the vendor. Do not switch off Memory Integrity. |
| **45** | `CM_PROB_PHANTOM` | "Currently, this hardware device is not connected to the computer." For a paired peripheral this means it is off or out of range. | Turn it on; if it stays "not connected", `-Mode Forget -Device <name>` and pair again. |
| **10** | `CM_PROB_FAILED_START` | Windows cannot start the driver. | Try a USB 2.0 port, remove + rescan, update the driver. |
| **43** | `CM_PROB_FAILED_POST_START` | The device failed to start. | Remove + rescan, try another port, update the driver. |
| **32** | `CM_PROB_DISABLED_SERVICE` | A service the device needs is disabled. | Re-enable `bthserv` and the device association service. |
| **52** | `CM_PROB_UNSIGNED_DRIVER` | The driver is not signed. | Use a signed driver (vendor or Windows Update). |
| **22** | `CM_PROB_DISABLED` | The device is **disabled**. This is not an error - it is how a parked radio looks. | `-Mode Rollback` re-enables it. |
| **14** | `CM_PROB_NEED_RESTART` | A reboot is required. | Restart Windows. |
| **24** | `CM_PROB_DEVICE_NOT_THERE` | The device is not present. | Plug it in, or pair the peripheral again. |

## Things that are not driver problems

* **The software radio switch** — Windows has a machine-wide radio switch
  (Settings → Bluetooth, or the Fn/F11 radio key). While it is off, every
  Bluetooth device looks broken. BTFix reports it as a finding.
* **The services** — `bthserv` (Bluetooth Support Service) must be running;
  `DeviceAssociationService` and `DeviceInstall` matter for pairing.
* **USB power management** — "Allow the computer to turn off this device to
  save power" makes cheap dongles drop out of the stack after a few idle
  minutes. `.\BTFix.ps1 -Mode Fix -DisableUsbSuspend` clears the flag.
* **USB 3.x ports** — some older CSR dongles fail to enumerate on a USB 3
  root hub. Try a USB 2.0 port.
* **Two radios** — if the dongle works only while the internal adapter is
  disabled, some devices (AirPods, some fitness bands) bind to whichever
  radio is active. Pick one and keep it.
* **Stale driver stores** — a previously installed vendor driver can keep
  failing after an update. `pnputil /remove-device` (not just "uninstall") is
  the reliable way to clear it.
* **Stale pairings** — a peripheral that was paired against a radio that is
  now gone can refuse to reconnect. Forget it and pair it again.

## Collecting a report for a bug

```powershell
.\BTFix.ps1 -Mode Report
```

writes a Markdown file (and prints it) containing every radio, its problem
code, the driver in use, the service states and the tool's classification.
Attach it to an issue - it removes an entire round of questions.

## Supported platforms

* Windows 10 1809+, Windows 11 (tested on 24H2)
* Windows PowerShell 5.1 and PowerShell 7+
* x64 and ARM64
* Administrator rights only for `Fix` / `Rollback` / `Forget`
