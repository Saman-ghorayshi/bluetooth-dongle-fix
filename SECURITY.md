# Security Policy

## Supported versions

The latest `main` branch is supported. Releases are published from tags.

## Reporting a vulnerability

Please open a **private** security advisory on the repository
(Security → Report a vulnerability) rather than a public issue. Include:

* what an attacker could achieve,
* the steps to reproduce it,
* your Windows version and the output of `.\BTFix.ps1 -Mode Report`.

You can expect an initial response within 7 days.

## What this tool does with your machine

* It reads the Bluetooth device inventory (read-only).
* With `-Mode Repair` / `-Mode Rollback` it enables/disables **Bluetooth-class
  devices only**, restarts `bthserv`, and writes snapshots and logs under
  `%LOCALAPPDATA%\BTFix`.
* It does **not** download or install drivers unless you explicitly pass
  `-SearchWindowsUpdate`.
* It never reads or transmits personal data; the tool works entirely offline.
