# How BTFix works

## The pipeline

```
BTFix.ps1  (CLI: modes, elevation, logging)
   │
   └── src/BTFix.psm1  (engine)
         ├── Get-BTFixRadio        inventory: radios, problem codes, drivers
         ├── Get-BTFixDiagnosis     classification + recommended actions
         ├── New-BTFixBackup        snapshot (JSON) for rollback
         ├── Invoke-BTFixRepair     the repair pipeline
         ├── Invoke-BTFixRollback   undo the last repair
         ├── Invoke-BTFixWindowsUpdate  optional driver search
         └── Write-BTFixReport      Markdown diagnostics
```

## Why a snapshot first

Every mutating step is preceded by a snapshot of the radio state
(`%LOCALAPPDATA%\BTFix\backups\btfix-<timestamp>.json`). `Rollback` reads the
newest snapshot and re-enables exactly the radios that the repair disabled.
The snapshot is plain JSON so it can be inspected, diffed or restored by
hand.

## The repair steps, and why each exists

1. **Restart `bthserv`** — releases the Bluetooth stack so a radio can grab
   it. A stuck service is enough to keep a dongle in Code 31.
2. **Remove + rescan the broken radio** — `pnputil /remove-device` followed by
   `pnputil /scan-devices` re-enumerates the device from scratch. This alone
   fixes a surprising share of cases, because the failed device node is
   cached by the stack.
3. **Break the conflict** — if the radio is still Code 31 *and* another radio
   is healthy, the healthy one is disabled and the hardware is re-scanned.
   Windows allows a single radio to own the stack, so this is the actual fix
   for the "dongle not recognized" class of bugs.
4. **Verify** — the radio must end up `Status: OK` with problem code 0.

## Why the tool refuses to guess

* `Diagnose` never writes to the system, so it is safe to run on a work
  machine and to paste the output into an issue.
* `Repair` never downloads or installs anything unless `-SearchWindowsUpdate`
  is passed explicitly.
* Only devices in the **Bluetooth** class are touched. Wi-Fi, USB and HID
  devices are never modified — disabling the wrong radio would break
  connectivity.

## Elevation

The CLI re-launches itself elevated (`Start-Process -Verb RunAs`) when the
mode needs administrator rights, forwarding the original arguments. If
elevation is declined, the tool exits with code 2 instead of failing halfway
through. `-NoElevation` disables the prompt.

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
* Two PowerShell pitfalls are handled explicitly and are worth knowing if you
  fork the code:
  * an `if` used as an expression unrolls a single-element array into a
    scalar (breaks `.Count` under `Set-StrictMode`);
  * an empty array binds as `$null` to an `[object[]]` parameter.
