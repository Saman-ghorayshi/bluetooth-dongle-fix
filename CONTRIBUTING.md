# Contributing to BTFix

Thanks for helping! This project is small on purpose, so the rules are simple.

## Ground rules

* **Never touch a real Bluetooth stack in a pull request.** All logic that
  touches hardware lives behind small functions that the test suite mocks.
* **Keep PowerShell 5.1 compatibility.** The tool must run on a stock
  Windows box. Avoid `??`, ternary operators and other PS7-only syntax, and
  save files as UTF-8 **with BOM**.
* **Every behaviour change needs a test.** The suite is dependency free:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`.

## Development loop

```powershell
git clone https://github.com/Saman-ghorayshi/bluetooth-dongle-fix
cd bluetooth-dongle-fix
.\tests\run-tests.ps1        # run the suite
.\BTFix.ps1 -Mode Diagnose   # try it on your own machine
```

## Adding a new chipset profile

1. Collect the hardware id: `pnputil /enum-devices /class Bluetooth`.
2. Add the id and the matching driver name to the table in
   `docs/troubleshooting.md`.
3. If the chipset needs a vendor driver, document the download link and the
   signing situation (old CSR packages are unsigned for Windows 11).

## Adding a new repair step

1. Put the step in `Invoke-BTFixRepair` in `src/BTFix.psm1`.
2. Make it safe: guard it with `ShouldProcess` so `-WhatIf` works.
3. Add a test with a mocked inventory.
4. Document it in `docs/how-it-works.md`.

## Commit style

Short imperative subject, e.g. `fix: treat problem code 22 as disabled`.
One logical change per commit.
