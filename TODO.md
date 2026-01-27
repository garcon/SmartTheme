# SmartTheme — TODO

Tento soubor obsahuje aktuální plán práce a stav úkolů. Je zrcadlem interního todo-listu, aby byl přehledný i v repozitáři.

## Stav (aktuální)

- [x] Consolidate config & DI
  - Vytvořen `$Config` a funkce byly parametrizovány. (Soubory: `SmartTheme.ps1`, `lib/SmartThemeModule.psm1`)

- [ ] Add scheduling unit tests
  - Přidat Pester testy pro plánování (mocky pro `schtasks`/`cmd`) — soubor `tests/Scheduling.Tests.ps1`.

- [ ] Rename exported functions to approved verbs
  - Doplnit přejmenování/exporty na schválené PowerShell verby (např. `Schedule-ThemeSwitch` -> `Register-ThemeSwitch`, `Schtasks-CreateForCurrentUser` -> `Register-SmartThemeUserTask`) a opravit call sites.

- [x] Run full test suite & CI validation
  - CI workflow `/.github/workflows/pester.yml` přidán; lokální Pester byl spuštěn (dřívější běh: Passed: 11, Failed: 0).

- [x] Run PSScriptAnalyzer locally
  - Analyzer spuštěn; provedeny automatické opravy nízkorizikových varování.

- [x] Auto-fix low-risk analyzer warnings
  - Odstraněno `Write-Host`, vyřešeny prázdné catch bloky, přidáno `SupportsShouldProcess` tam, kde bylo potřeba, refaktoring logování (`Write-SmartThemeLog`).

- [ ] Full cleanup — PSScriptAnalyzer green (IN-PROGRESS)
  - Dokončit zbývající varování: převést zbývající volání `Write-Log` → `Write-SmartThemeLog`, vyřešit PSReviewUnusedParameter refaktory nebo explicitní použití parametrů, zajistit `ShouldProcess` pro všechny state-changing funkce a opravit případné BOM/encoding poznámky.
  - Next immediate action: VOLBA A — spustit lokálně Pester + Invoke-ScriptAnalyzer a iterovat opravy až do zeleného stavu.

## Příště (co se provede jako první — volba A)

1. Spustím všechny Pester testy v `tests\` a pošlu report (passed/failed a krátké chyby).
2. Spustím `Invoke-ScriptAnalyzer` nad produkčními soubory (`lib\*.ps1`, `SmartTheme.ps1`) a pošlu seznam zbývajících varování.
3. Postupně opravím zbývající varování a znovu spustím testy/analyzer dokud nebude zeleno.

## Rychlé příkazy (pwsh)

Spuštění testů (lokálně):

```powershell
# z kořenového adresáře repo
Import-Module Pester -MinimumVersion 3.4 -Force
Invoke-Pester -Script .\tests
```

Spuštění PSScriptAnalyzer (produkční soubory):

```powershell
Import-Module PSScriptAnalyzer -ErrorAction Stop
Invoke-ScriptAnalyzer -Path .\lib\*.ps1, .\SmartTheme.ps1 -Recurse -Severity Warning | Format-Table -AutoSize
```

> Poznámka: pokud PSScriptAnalyzer hlásí varování ohledně PSReviewUnusedParameter, je lepší nejprve zkusit refaktorovat kód tak, aby analýza poznala použití parametru (ne potlačovat pravidlo), kromě případů, kdy je použití skutečně dynamické.

## Kontakt / další kroky

Napiš, až budeš ready pokračovat — příště spustím volbu A (testy + analyzer) a budu opravovat, dokud nebude čistý výsledek.

## Pre-commit checklist & unblock procedure

- Před commitem (doporučeno):
  1. Spusť Pester (`Invoke-Pester -Script .\tests`) a ujisti se, že testy procházejí.
  2. Spusť PSScriptAnalyzer nad produkčními soubory (`Invoke-ScriptAnalyzer -Path .\lib -Recurse`) a zkontroluj varování.

- Pokud testy selžou a chceš committnout dokumentaci rychle:
  - Vytvoř novou branch (např. `feature/psscleanup`) a committni průběžné změny tam.
  - Nebo pokud selhávají scheduling testy kvůli parsování při `Import-Module`, dočasně uprav test `tests/Scheduling.Tests.ps1` tak, aby modul dot-sourcoval místo `Import-Module` (test-only změna) — to odblokuje běh testů:

```powershell
# v tests/Scheduling.Tests.ps1 místo:
Import-Module $modulePath -Force -ErrorAction Stop

# použij:
. $modulePath
```

- Doporučené commit zprávy (atomické):
  - `docs: add TODO.md and copilot instructions`
  - `fix: small logging/name cleanup`

Tento postup zapisuj do TODO a používej jej jako krátký checklist před pushnutím do hlavní větve.
