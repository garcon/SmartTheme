# SmartTheme

SmartTheme je jednoduchý PowerShell skript, který přepíná Windows téma (světlé/tmavé)
podle místního času východu a západu slunce.

Obsah složky
- `SmartTheme.ps1` — hlavní skript (zjišťuje polohu, volá sunrise-sunset API, přepíná registr a plánuje přepnutí).
- `SmartThemeSwitch-Ensure.xml` — doporučené Task Scheduler XML (auto-generováno).
- `location.json` — cache polohy a časů v UTC.
- `smarttheme.log` — log skriptu (ořezán na posledních N řádek).
- `lib/` — moduly (localization, logging, scheduler, utils).

Rychlé použití
- Okamžité přepnutí na tmavé téma:

```powershell
pwsh -NoProfile -File .\SmartTheme.ps1 -Dark
```

- Okamžité přepnutí na světlé téma:

```powershell
pwsh -NoProfile -File .\SmartTheme.ps1 -Light
```

- Pouze aktualizovat plán (nezmění aktuální téma):

```powershell
pwsh -NoProfile -File .\SmartTheme.ps1 -Schedule
```

Import doporučeného XML do Task Scheduler (vyžaduje administrátorská práva):

```powershell
schtasks /Create /TN "SmartThemeSwitch-Ensure" /XML "%LOCALAPPDATA%\SmartTheme\SmartThemeSwitch-Ensure.xml" /F
```

Důležité poznámky
- Pokud vidíte chyby typu "Přístup byl odepřen", spusťte skript jako administrátor pro import XML.
- Cache polohy je v `location.json` — pokud API selže, použije se cache nebo zadané souřadnice.

Developerské poznámky
- Moduly jsou v `lib/` a skript používá DI (`-Config`) pro testovatelnost.
- Spuštění testů:

```powershell
pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script .\tests"
```

Spuštění lokálních kontrol (pinned Pester + PSScriptAnalyzer):

```powershell
pwsh -NoProfile -File .\tools\run-local-checks.ps1
```

Více informací najdete v `CHANGES.md` a `lib/locales`.
