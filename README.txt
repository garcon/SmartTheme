SmartTheme — lokální složka používaná skriptem pro inteligentní přepínání tématu

Tato složka obsahuje cache a pomocné soubory používané PowerShell skriptem, který přepíná Windows téma (světlé/tmavé) podle východu a západu slunce.

Hlavní soubory a jejich účel:
  - `SmartTheme.ps1`              : hlavní skript. Zjišťuje polohu (ipapi nebo zadané souřadnice), volá API pro východ/západ slunce, nastavuje registr Windows pro AppsUseLightTheme/SystemUsesLightTheme a plánuje další přepnutí.
  - `SmartThemeSwitch-Ensure.xml` : doporučené XML pro import do Windows Task Scheduler (auto-generováno). Obsahuje TimeTrigger + BootTrigger + LogonTrigger, nastavení StartWhenAvailable=true a WakeToRun=false. Akce spouští `SmartTheme.ps1 -Ensure`.
  - `location.json`              : cache polohy a UTC časů východu/západu (včetně timezone, timestampu a data). Slouží k omezení volání externího API.
  - `smarttheme.log`             : log skriptu (ořezán na posledních 500 řádek). Najdete zde historii volání API, přepínání tématu a informace o plánování úloh.
  - `README.txt`                 : tento soubor (aktualizovaný — popisuje chování a doporučené kroky).

Jak to funguje (stručně):
  1) Skript zjistí polohu (pokud nebyly zadány parametry `-Lat` a `-Lon`), pak zavolá `https://api.sunrise-sunset.org` pro časy východu/západu (UTC) a převede je do lokálního timezone.
  2) Na základě aktuálního času a současného tématu (čtení z registru `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`) skript přepne téma nebo pouze naplánuje přepnutí.
  3) Naplánování: preferuje import přes XML (pokud je PowerShell spuštěn s administrátorskými právy), jinak použije Register-ScheduledTask nebo jako fallback `schtasks.exe` pro aktuálního uživatele. Script vytváří také fallback ONSTART a ONLOGON úlohy.

Užitečné příkazy (spusťte jako administrátor, pokud chcete importovat úlohu do systémového Task Scheduler):

Příklad — spustit skript s parametrem `-Schedule` ve zvýšeném režimu (spustí se UAC prompt):

```powershell
Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Martin\OneDrive\Dokumenty\PowerShell\Scripts\mode.ps1" -Schedule' -Verb RunAs
```

Příklad — importovat vygenerovaný XML do Task Scheduler ručně:

```powershell
schtasks /Create /TN "SmartThemeSwitch-Ensure" /XML "%LOCALAPPDATA%\SmartTheme\SmartThemeSwitch-Ensure.xml" /F
```

Rychlé lokální testy (bez importu úlohy):
  - `SmartTheme.ps1 -Dark`   → okamžitě nastaví tmavé téma a naplánuje další přepnutí.
  - `SmartTheme.ps1 -Light`  → okamžitě nastaví světlé téma a naplánuje další přepnutí.
  - `SmartTheme.ps1 -Schedule` → pouze aktualizuje plán (nezměňuje aktuální téma).

Důležité poznámky a tipy pro řešení problémů:
  - Pokud vidíte v `smarttheme.log` chyby typu "Přístup byl odepřen" při vytváření úloh, skript běžel bez administrátorských práv a použil fallback (pokud to systém dovolil). Pro spolehlivé importování plné XML úlohy spusťte skript jako administrátor.
  - Skript ukládá cache do `location.json`; pokud volání `ipapi.co` nebo `sunrise-sunset` selžou, použije cache (pokud existuje) nebo záložní souřadnice (Praha).
  - Úlohy jsou konfigurovány tak, aby neprobouzele počítač (`WakeToRun=false`) a aby se spustily pokud byly vynechány (`StartWhenAvailable=true`).
  - V případě potřeby můžete skriptu předat přesné souřadnice (`-Lat <číslo> -Lon <číslo>`) pro přesnější chování a méně závislostí na IP geolokaci.

Další možnosti a vylepšení (doporučené):
  - Pokud chcete větší kontrolu, spusťte import XML jednou jako administrátor — to zajistí konzistentní nastavení triggerů a runlevelu.
  - Pro více robustní mapování časových pásem lze rozšířit interní IANA→Windows mapu v `SmartTheme.ps1`.
  - Kontrola logu (`smarttheme.log`) je první krok při diagnostice nečekaného chování.

  Vývojáři & testy:
    - Modulární rozhraní: lokalizace a logging jsou nyní v `lib/` jako modulové komponenty (např. `LocalizationModule.psm1`, `LoggingModule.psm1`, `Config.psm1`, `Scheduler.psm1`, `Utils.psm1`). Hlavní skript `SmartTheme.ps1` používá `Get-DefaultConfig` a moduly místo globálních funkcí.
    - Spuštění testů lokálně:
        pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script .\tests"
    - Spuštění analýzy:
        pwsh -NoProfile -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser; Import-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path . -Recurse"
    - CI: workflow nyní spouští Pester a PSScriptAnalyzer a build selže pokud analyzer najde varování/chyby.

  Poznámky k lokalizaci:
    - Česká lokalizace (`lib/locales/cs.json`) byla upravena na ASCII-only text (bez diakritiky) kvůli konzistentnímu chování v různých konzolích a v testech. K dispozici je `ConvertTo-ComparableString` v `lib/Utils.psm1` pro porovnávání bez diakritiky.

Pokud chceš, mohu připravit upravené XML (jiné startBoundary nebo jiné jméno úlohy), automatický příkaz pro import jako Administrátor, nebo drobná vylepšení skriptu — napiš, co preferuješ.
SmartTheme — local folder used by the mode.ps1 script

Files created/used by the script:
  - SmartThemeSwitch-Ensure.xml : Recommended Task Scheduler XML (auto-generated).
  - location.json             : cached location & sunrise/sunset UTC times (written by mode.ps1).
  - smarttheme.log            : script log (trimmed to the last 100 lines).
  - README.txt                : this file.

Notes:
  - Importing the XML into Task Scheduler requires Administrator rights.

Recommended actions:
  - To let the script generate and import the recommended task automatically, run the script as Administrator:
      Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Martin\AppData\Local\SmartTheme\SmartTheme.ps1" -Schedule' -Verb RunAs

  - Or import the XML manually as Administrator:
      schtasks /Create /TN "SmartThemeSwitch-Ensure" /XML "%LOCALAPPDATA%\SmartTheme\SmartThemeSwitch-Ensure.xml" /F

  - The generated task uses StartWhenAvailable=true, WakeToRun=false and runs mode.ps1 with the -Ensure flag so the task recomputes the proper theme instead of forcing a mode.
