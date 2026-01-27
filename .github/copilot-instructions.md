# Copilot / AI Agent guidance for SmartTheme

This file contains focused, actionable instructions to help an AI coding agent become productive in this repository quickly. Keep suggestions small and verifiable: make a change, run the tests, run static analysis, iterate.

1) Big picture (what this repo does)
- SmartTheme is a small PowerShell tool that toggles Windows light/dark theme based on local sunrise/sunset and schedules future toggles.
- Entrypoint: `SmartTheme.ps1`. Helpers and exported functions live in `lib/` (notably `lib/SmartThemeModule.psm1`, `lib/Logging.ps1`, `lib/Localization.ps1`, `lib/TimeZoneHelpers.ps1`).
- Tests are in `tests/` (Pester). CI workflow: `.github/workflows/pester.yml`.

2) Architecture & boundaries (how code is organized)
- `SmartTheme.ps1` is the CLI script: parses args, builds a small `$Config` object and calls into library functions.
- `lib/SmartThemeModule.psm1` contains most logic that should be unit-tested and refactored: theme get/set, scheduling, task XML export/import, wrappers for external processes, cache helpers, and retry helper.
- `lib/Logging.ps1` and `lib/Localization.ps1` are cross-cutting: use `Translate('<KEY>', ...)` to fetch localized messages from `lib/locales/*.json` and `Write-SmartThemeLog` (or `Write-Log` historically) for logging.

3) Important project-specific patterns (follow these exactly)
- Dependency injection via a `-Config` object: many functions accept `[psobject]$Config` and fallback to defaults (e.g., RunnerExe, SchtasksExe, CmdExe, CacheDir, CacheFile, RegPath). Prefer using the `-Config` param in tests and when refactoring.
- External system calls are wrapped and testable: use `Invoke-Schtask` (wrapper for `schtasks.exe`) and `Invoke-Cmd` (wrapper for `cmd.exe`). Do not call `schtasks.exe`/`cmd.exe` directly in tests or new code—use the wrappers so they can be mocked.
- Scheduling helpers: scheduling logic lives in `Register-ThemeSwitch` / `Register-SmartThemeUserTask` (older code used `Schedule-ThemeSwitch`/`Schtasks-CreateForCurrentUser`). Search both names when changing scheduling.
- State-changing operations must use ShouldProcess: functions that write registry, modify scheduled tasks, or write caches use `[CmdletBinding(SupportsShouldProcess=$true)]` and call `$PSCmdlet.ShouldProcess(...)`. Preserve that pattern when adding or renaming functions.
- Localization: message keys are under `lib/locales/*.json`. Use `Translate('<KEY>', $args...)` to build strings used in logs and tests. Tests assert on translation keys/outputs, so avoid changing keys without updating tests.

4) Developer workflows & commands (how to run things locally)
- Run unit tests (PowerShell / Pester):

```powershell
Import-Module Pester -MinimumVersion 3.4 -Force
Invoke-Pester -Script .\tests
```

- Run static analysis (PSScriptAnalyzer) — prefer the helper if present:

```powershell
# Simple direct run
Import-Module PSScriptAnalyzer -ErrorAction Stop
Invoke-ScriptAnalyzer -Path .\lib\*.ps1, .\SmartTheme.ps1 -Recurse -Severity Warning | Format-Table -AutoSize

# Or use helper script if available
.\tools\run_analyzer.ps1
```

- Run the script manually (Windows):

```powershell
# Toggle theme (no elevation) and schedule
pwsh -NoProfile -File .\SmartTheme.ps1

# Update only schedule (no theme change)
pwsh -NoProfile -File .\SmartTheme.ps1 -Schedule
```

5) Tests & mocking tips (how AI should change code safely)
- Tests expect wrappers and DI: when adding features that invoke external commands, add parameters to accept alternate `RunnerExe`, `SchtasksExe`, `CmdExe` or accept `-Config` so tests can inject fakes.
- Prefer mocking `Invoke-Schtask` and `Invoke-Cmd` in Pester tests instead of trying to stub `schtasks.exe` directly. Example: `Mock -CommandName Invoke-Schtask -MockWith { 'OK' }` (Pester v3 style).
- Localization tests exist (`tests/Localization.Tests.ps1`) — prefer calling `Translate()` rather than hardcoding strings in code so tests keep working.

6) Integration points & external dependencies
- External commands/APIs used:
  - `schtasks.exe` and Windows Scheduled Tasks API (`Register-ScheduledTask`, `Unregister-ScheduledTask`, etc.)
  - `cmd.exe` used for reliable redirection when exporting task XML
  - REST APIs: `https://ipapi.co/json/` (for geolocation) and `https://api.sunrise-sunset.org/json` (for sunrise/sunset). These are wrapped by `Invoke-RestWithRetry`.
- When changing scheduling code, be aware of two approaches present: using scheduled task XML import (preferred when elevated) and using `schtasks.exe` when not elevated.

7) Conventions to preserve (naming & behavior)
- Keep messages localized and use `Translate` keys. Locale files are `lib/locales/en.json`, `cs.json`, `de.json`.
- Use `Write-SmartThemeLog` / `Write-Log` consistently for logs; avoid `Write-Host`.
- Prefer approved PowerShell verbs for exported functions (the codebase is already migrating: `Schedule-ThemeSwitch` → `Register-ThemeSwitch`, `Schtasks-CreateForCurrentUser` → `Register-SmartThemeUserTask`). If you rename functions, update all call sites in `SmartTheme.ps1`, `lib/SmartThemeModule.psm1`, and tests.

8) Files to inspect when changing behavior
- `SmartTheme.ps1` — CLI & orchestration
- `lib/SmartThemeModule.psm1` — core logic and exported functions
- `lib/Logging.ps1` — logging helpers
- `lib/Localization.ps1` and `lib/locales/*.json` — translations
- `tests/*.Tests.ps1` — tests to run/modify
- `.psscriptanalyzer.psd1` and `tools/run_analyzer.ps1` — static analysis config and helper
- `.github/workflows/pester.yml` — CI pipeline

9) Quick rules for AI edits
- Make behavioral changes in `lib/SmartThemeModule.psm1` and keep `SmartTheme.ps1` as the thin orchestrator.
- When adding or renaming exported functions, update `Export-ModuleMember -Function *` usage and all call sites and tests.
- After any change: run Pester and Invoke-ScriptAnalyzer. Fix failing tests or analyzer warnings before proposing a PR.

If anything here is unclear or you want me to include short code snippets (example mocks, a typical unit test for `Register-ThemeSwitch`, or a sample translation key), tell me what you'd like and I will update this file.

10) Recent changes (keep in mind)
- The `cs` locale was converted to ASCII-only strings (diacritics removed) to avoid console/encoding issues on some Windows setups. Tests were updated accordingly.
- Logging now prefers UTF-8 with BOM for the log file and attempts to set the PowerShell console to UTF-8 at startup. The log writer trims files to keep the last 500 lines.
- `Translate` is exposed so modules can call localization at runtime and a `Write-Log` wrapper exists for compatibility with older code.
- Tests include non-interactive runner scripts under `tests/` and the suite is safe to run locally; avoid running test helpers that try to elevate UAC automatically.

11) Guidance when changing localization
- If you revert the ASCII change and restore diacritics in `lib/locales/cs.json`, update any tests that assert exact strings (e.g., `tests/Smoke.Tests.ps1`). Alternatively, update tests to compare using a normalization helper that strips diacritics before asserting.
