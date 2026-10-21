# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
