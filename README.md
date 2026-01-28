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

Alternativně lze po instalaci doplňku spouštět skript z příkazové řádky pomocí příkazu `theme` (pokud máte přidaný shim do PATH).

Krátký příkaz `theme` (shim)

- Instalace (one-time): spusťte instalační skript, který zkopíruje `theme.cmd` do `%USERPROFILE%\bin` a přidá tento adresář do uživatelské proměnné `PATH`:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\install-shim.ps1
```

- Poznámka: `setx` aktualizuje uživatelský `PATH` pro nové relace — otevřete novou PowerShell/CMD relaci (nebo se odhlaste/přihlaste), aby se změna projevila. Pro okamžité použití v aktuálním shellu můžete přímo přidat `bin` do `PATH`:

```powershell
$env:PATH = "$env:USERPROFILE\bin;" + $env:PATH
```

- Alternativní přímé spuštění bez instalace:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\SmartTheme\SmartTheme.ps1 -Schedule
```

- Příklad použití po instalaci:

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

Poznámka o analyzátoru kódu
- Výstupy PSScriptAnalyzeru (soubory `analyzer*.txt` nebo `analyzer-*.txt`) nejsou součástí repozitáře — jsou to generované artefakty a jsou ignorovány pomocí `.gitignore`.

Pokud chcete spustit analyzátor lokálně a uložit výstup ručně, můžete to udělat takto:

```powershell
pwsh -NoProfile -File .\tools\run-local-checks.ps1 | Tee-Object tools\analyzer-output.txt
```

V produkci doporučujeme spouštět analýzu v CI a ukládat výsledky jako artefakty workflow.

Developer tip: enable repository hooks
- This repo includes a pre-commit hook in `.githooks/pre-commit` which updates `SmartTheme.ps1.sha256` automatically before every commit.
- To enable hooks for your local clone run:

```powershell
git config core.hooksPath .githooks
```

After this the `pre-commit` hook will compute and stage the checksum file automatically.

Jak to funguje (kratce)
- Naplánované "ONCE" úlohy nyní spouštějí skript s `-Ensure` (nikoli s explicitním `-Light`/`-Dark`) — to zabraňuje nežádoucím přepnutím, pokud se úloha spustí opožděně; startup/logon úlohy a shim také používají `-Ensure`.
- Při zjišťování polohy skript preferuje `location.json` pokud jeho `timestamp` je mladší než 1 hodina — zamezí tak zbytečným síťovým voláním.
- Pokud vedle `SmartTheme.ps1` existuje soubor `SmartTheme.ps1.sha256`, skript ověří integritu pomocí SHA256 před pokračováním.
