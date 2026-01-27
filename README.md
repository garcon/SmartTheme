# SmartTheme

SmartTheme je jednoduchý PowerShell skript, který přepíná Windows téma (světlé/tmavé)
podle místního času východu a západu slunce.

Obsah složky
- `SmartTheme.ps1` — hlavní skript (zjišťuje polohu, volá sunrise-sunset API, přepíná registr a plánuje přepnutí).
- `SmartThemeSwitch-Ensure.xml` — doporučené Task Scheduler XML (auto-generováno).
- `location.json` — cache polohy a časů v UTC.
- `smarttheme.log` — log skriptu (ořezán na posledních N řádek).
  
Poznámka: `location.json` a `smarttheme.log` nejsou soubory v repozitáři — vznikají automaticky při prvním spuštění skriptu a jsou uloženy do `%LOCALAPPDATA%\SmartTheme`.
- `lib/` — moduly (localization, logging, scheduler, utils).

Rychlé použití
- Okamžité přepnutí na tmavé téma:

```powershell
pwsh -NoProfile -File .\SmartTheme.ps1 -Dark
```

Alternativně lze po instalaci doplňku spouštět skript z příkazové řádky pomocí příkazu `theme` (pokud máte přidaný shim do PATH nebo jste spustili `tools/add-path.ps1`).
Krátký příkaz `theme`
- Po instalaci můžete spouštět skript také z příkazové řádky pomocí příkazu `theme`.
- Shim `theme.cmd` lze umístit do `%LOCALAPPDATA%\SmartTheme` a tuto složku přidat do proměnné `PATH` (např. pomocí `tools/add-path.ps1`).
- Příklad použití:

```powershell
theme -Schedule
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

Jak to funguje (kratce)
- Naplánované "ONCE" úlohy spouštějí skript s explicitním módem (`-Light` nebo `-Dark`) v čase východu/západu, takže po rozbřesku bude systém nastaven na světlé a po soumraku na tmavé.
- Startup / Logon úlohy a shim `-Ensure` spouští skript v režimu `-Ensure` (udržuje očekávaný stav při startu/hlášení uživatele), proto jsou ponechány jako samostatné úlohy.
- Při zjišťování polohy skript preferuje `location.json` pokud jeho `timestamp` je mladší než 1 hodina — zamezí tak zbytečným síťovým voláním.
- Pokud vedle `SmartTheme.ps1` existuje soubor `SmartTheme.ps1.sha256`, skript ověří integritu pomocí SHA256 před pokračováním.
