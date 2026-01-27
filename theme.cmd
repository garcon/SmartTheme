@echo off
REM Cross-shell shim to run SmartTheme from any terminal via `theme`
REM Forwards all arguments to pwsh and the SmartTheme.ps1 script.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\SmartTheme\SmartTheme.ps1" %*
