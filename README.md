# Symcon_CI

Zentrale Prüfung für eigene IP-Symcon-Module. Ein Skript, das lokal vor dem Commit und in GitHub Actions identisch läuft, plus ein wiederverwendbarer Workflow, den jedes Modul mit einer Zeile aufruft. Die Module selbst enthalten nur `.style` und, falls gewünscht, `tests`. Änderungen an der Prüfung passieren hier an einer Stelle.

## Was geprüft wird

`scripts/check.php` führt im Wurzelverzeichnis des Moduls nacheinander aus:

| Schritt | Inhalt |
| --- | --- |
| PHP-Syntax | `php -l` für alle PHP-Dateien |
| JSON-Syntax | alle `*.json` müssen gültiges JSON sein |
| StylePHP json-check | `php .style/json-check.php` |
| php-cs-fixer | Prüfmodus mit `.style/.php-cs-fixer.php` (php-cs-fixer v3, `--allow-risky=yes`, `PHP_CS_FIXER_IGNORE_ENV=1`) |
| PHPUnit (optional) | nur wenn `tests/` existiert: mit `phpunit.xml` (bzw. `tests/phpunit.xml`), sonst mit `tests/bootstrap.php`. Ohne Tests: "übersprungen", kein Fehler |

Ausgeschlossen sind `.git`, `.style`, `.ci`, `vendor`, `node_modules` und `tests/stubs`. Übersprungene Schritte werden immer angezeigt. Mit `--strict` zählen sie als Fehler. Mit `--only=style` laufen nur JSON-Syntax, json-check und php-cs-fixer (Workflow `style.yml`), mit `--only=tests` nur PHP-Syntax und PHPUnit (Workflow `tests.yml`). Ohne `--only` läuft alles.

## Was ein Modul enthält

Nur das:

- `.style` als Git-Submodul von `https://github.com/symcon/StylePHP`
- optional `tests/` mit den Tests, `bootstrap.php` (und optional `phpunit.xml`) und `tests/stubs` als Git-Submodul von `https://github.com/symcon/SymconStubs`
- `.github/workflows/style.yml` und `.github/workflows/tests.yml`: je ein kurzer Aufruf des zentralen Workflows (Vorlagen `templates/module-style.yml` und `templates/module-tests.yml`, zeigen auf `Schnittcher/Symcon_CI@v1`)

Keine `composer.json`, kein `vendor/` und kein Submodul von `Symcon_CI` im Modul.

## Lokal ausführen

Im Modulordner:

```bash
symcon-check
```

Der Wrapper `symcon-check.bat` liegt in der lokalen Entwicklungsumgebung `C:\Symcon-Entwicklung` und ruft `scripts/check.php` aus der Arbeitskopie dieses Repositories auf. PHP, php-cs-fixer und PHPUnit liegen ebenfalls dort (`php\`, `php-cs-fixer-v3.phar`, `phpunit.phar`).

## Entwicklungsumgebung anlegen

`scripts/setup-env.ps1` prüft die Umgebung und legt Fehlendes an (PHP aus den offiziellen Quellen mit Prüfsumme, php-cs-fixer, PHPUnit, Composer, Wrapper, Benutzer-Pfad). Wiederholbar, mit `-Check` nur prüfen, mit `-Update` alles neu laden:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup-env.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup-env.ps1
```

Einrichtung im Einzelnen: siehe das Regelwerk (`standards/SETUP.md`).

## Versionen

- Module rufen den Workflow mit `@v1` auf. Der Tag `v1` wird bewusst auf neue, kompatible Stände weitergeschoben. Das Skript wird in der CI ebenfalls über `ci-ref` (Standard `v1`) geladen.
- Inkompatible Änderungen erscheinen als `v2`. Module stellen dann bewusst um.
- Lokal läuft der ausgecheckte Stand dieses Repositories. Damit lokal und CI übereinstimmen, wird `v1` nur auf den Stand von `main` verschoben, den du lokal auch nutzt.

## Herkunft

Orientiert an `Burki24/Symcon_ModuleCI` (MIT) und der offiziellen Style-Action `symcon/action-style`. Dieses Repository führt deren Prüfbefehle direkt aus und hängt nicht von diesen Repositories ab.
