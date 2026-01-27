# Changelog

All notable changes to this project are documented in this file.

## v2026-01-27 — 2026-01-27

### Added
- `tools/run-local-checks.ps1` — helper to run pinned Pester (v3.4) and `PSScriptAnalyzer` locally.

### Changed
- Tests and mocks updated to use approved verbs and be analyzer-friendly (`Register-ThemeSwitch`, `Register-SmartThemeUserTask`, `New-SmartThemeTaskXml`).
- Improved logging and localization: UTF-8/BOM handling and automatic log trimming to reduce repo noise.
- Small refactors across `lib/` to improve DI and testability (accept `-Config`, add `ShouldProcess` to state-changing functions).

### Fixed
- Resolved multiple `PSScriptAnalyzer` findings by referencing unused test parameters and renaming functions to approved verbs. All tests pass and analyzer reports no findings.

## Previous entries

### 2025-11-02 — SmartTheme localization sweep

- Localized all user-facing log strings in `SmartTheme.ps1`.
  - Replaced literal `Write-Log` messages with `Write-Log (Translate 'KEY' <args>)` calls.
- Fixed `lib/Localization.ps1` `Translate()` formatting to correctly use PowerShell `-f` with a safe fallback.
- Added/updated Pester tests: `tests/Localization.Tests.ps1`, `tests/Smoke.Tests.ps1`.

Notes
- See Git history for older entries.
