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

## v2026-01-28 — 2026-01-28

### Added
- `SmartTheme.ps1.sha256` — optional SHA256 checksum for `SmartTheme.ps1`; script verifies integrity when present.

### Changed
- `SmartTheme.ps1` now prefers recent `location.json` cache (if `timestamp` < 1 hour) to avoid unnecessary IP-based geolocation calls.
- `Register-ThemeSwitch` schedules ONCE tasks to run the script with explicit `-Light`/`-Dark` at sunrise/sunset; startup/logon tasks continue to run `-Ensure`.
- `README.md` and `.github/copilot-instructions.md` updated with notes about the `theme` shim, runtime files (`location.json`, `smarttheme.log`), cache behavior, and checksum verification.

### Fixed
- Scheduler: ensure ONCE scheduled tasks apply explicit mode flags so the UI is set to Light after sunrise and Dark after sunset.
- Various small refactors and logging improvements; tests and PSScriptAnalyzer remain clean.

## Previous entries

### 2025-11-02 — SmartTheme localization sweep

- Localized all user-facing log strings in `SmartTheme.ps1`.
  - Replaced literal `Write-Log` messages with `Write-Log (Translate 'KEY' <args>)` calls.
- Fixed `lib/Localization.ps1` `Translate()` formatting to correctly use PowerShell `-f` with a safe fallback.
- Added/updated Pester tests: `tests/Localization.Tests.ps1`, `tests/Smoke.Tests.ps1`.

Notes
- See Git history for older entries.
