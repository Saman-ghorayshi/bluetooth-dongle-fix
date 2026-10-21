# How BTFix works

## The pipeline

```
BTFix.ps1  (CLI: modes, elevation, logging)
   │
   └── src/Findings.psm1   the checklist engine (what is wrong, and can we fix it)
         ├── src/BTFix.psm1        radios, diagnosis, backup, repair, rollback, report
         ├── src/Health.psm1       services, radio switch, pairings, USB power
         ├── src/ProblemCodes.psm1 the Microsoft CM_PROB_* table
         └── src/Chipsets.psm1     known chipset ids and where to get a driver
```

## Why a snapshot first

Every mutating step is preceded by a snapshot of the radio state
(`%LOCALAPPDATA%\BTFix\backups\btfix-<timestamp>.json`). `Rollback` reads the
newest snapshot and re-enables exactly the radios that the repair disabled.
The snapshot is plain JSON so it can be inspected, diffed or restored by hand.

## The repair steps, and why each exists

1. **Start the services** — `bthserv`, `DeviceAssociationService` and
   `DeviceInstall` must run before anything else can work. A service that is
   *disabled* (not just stopped) is set back to Manual and started.
2. **Restart `bthserv`** — releases the Bluetooth stack so a radio can grab
   it. A stuck service is enough to keep a dongle in Code 31.
3. **Remove + rescan the broken radio** — `pnputil /remove-device` followed by
   `pnputil /scan-devices` re-enumerates the device from scratch. This alone
   fixes a surprising share of cases, because the failed device node is
   cached by the stack.
4. **Break the conflict, but only in the right direction** — Windows lets one
   radio own the Bluetooth stack. The radio the user *wants* working wins:
   the one named with `-Radio`, otherwise the external dongle, otherwise the
   internal adapter. The other radio is parked so the wanted one can take
   over. If the *working* radio is not the broken one, BTFix leaves it alone
   and reports the broken one instead of trading a working adapter for a
   broken one.
5. **Re-enable the wanted radio** if it was merely disabled (problem code 22
   is intentional state, not a failure).
6. **Optional extras** — `-DisableUsbSuspend` clears the per-device
   "let Windows power this down" flag; `-ForgetStale` drops peripherals that
   are paired but not connected.
7. **Verify** — every radio must end up `Status = OK` with problem code 0.

## Why the tool refuses to guess

* `Check` never writes to the system, so it is safe to run on a work machine
  and to paste the output into an issue.
* `Repair` never downloads or installs anything unless `-SearchWindowsUpdate`
  is passed explicitly.
* Only devices in the **Bluetooth** class are touched. Wi-Fi, USB and HID
  devices are never modified — disabling the wrong radio would break
  connectivity.
* Findings that need a human (a blocked driver, a missing vendor driver, the
  software radio switch) are reported with instructions instead of a blind
  registry write.

## Telling a dongle from a built-in adapter

Topology cannot: a built-in radio is USB-attached internally, so its parent
chain ends at a PCI device either way. Windows groups devices that share a
physical chassis into a *container id*, and that is what BTFix uses:

* built-in radio → `{00000000-0000-0000-FFFF-FFFFFFFFFFFF}` (the system
  container)
* external dongle → its own container for the USB port it sits in

## Elevation

The CLI re-launches itself elevated (`Start-Process -Verb RunAs`) when the
mode needs administrator rights, forwarding the original arguments **one argv
entry each** (a single `"-Mode Fix"` string arrives as one positional
argument and the mode silently stays at its default). If elevation is
declined, the tool exits with code 2 instead of failing halfway through.
`-NoElevation` disables the prompt.

## Logging

Every run writes a transcript to
`%LOCALAPPDATA%\BTFix\logs\btfix-<timestamp>.log` containing the exact
`pnputil` invocations and their output, so a run can be reconstructed after
the fact.

## Compatibility notes

* The module targets **Windows PowerShell 5.1** as well as PowerShell 7, so it
  runs on a stock Windows box.
* Scripts are stored as UTF-8 **with BOM** — without it, Windows PowerShell
  5.1 mis-decodes non-ASCII characters and fails to parse the file.
* Nested `Import-Module` calls must not use `-Force`: in Windows PowerShell
  5.1 a forced re-import unloads the module and the session keeps a stale
  reference, so the functions disappear.
* Three PowerShell pitfalls are handled explicitly and are worth knowing if
  you fork the code:
  * an `if` used as an expression unrolls a single-element array into a
    scalar (breaks `.Count` under `Set-StrictMode`);
  * an empty array binds as `$null` to an `[object[]]` parameter;
  * a pipeline that yields one object has no `.Count` — wrap it in `@()`.
