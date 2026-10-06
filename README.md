# Symcon_CI

Zentrale Prüfung für eigene IP-Symcon-Module. Ein Skript, das lokal vor dem Commit und in GitHub Actions identisch läuft, plus ein wiederverwendbarer Workflow, den jedes Modul mit einer Zeile aufruft. Änderungen an der Prüfung passieren hier an einer Stelle.

## Was geprüft wird

`scripts/check.php` führt im Repository-Wurzelverzeichnis des Moduls nacheinander aus:

| Schritt | Inhalt |
| --- | --- |
| PHP-Syntax | `php -l` für alle PHP-Dateien |
| JSON-Syntax | alle `*.json` müssen gültiges JSON sein |
| StylePHP json-check | `php .style/json-check.php` |
| php-cs-fixer | Prüfmodus mit `.style/.php-cs-fixer.php` (php-cs-fixer v3, `--allow-risky=yes`, `PHP_CS_FIXER_IGNORE_ENV=1`) |
| PHPUnit | `vendor/bin/phpunit`, wenn `tests/` existiert |

Ausgeschlossen sind `.git`, `.style`, `.ci`, `vendor`, `node_modules` und `tests/stubs`. Übersprungene Schritte werden immer angezeigt. Mit `--strict` zählen sie als Fehler, mit `--skip-style` entfallen json-check und php-cs-fixer.

## Einbindung in ein Modul

Voraussetzungen im Modul-Repository: Git-Submodule `.style` (`https://github.com/symcon/StylePHP`) und `tests/stubs` (`https://github.com/symcon/SymconStubs`).

1. **CI:** `templates/module-workflow.yml` nach `.github/workflows/check.yml` kopieren. Der Aufruf zeigt auf `Schnittcher/Symcon_CI@v1`. Bei einem Fork den Account anpassen.
2. **Lokal:** dieses Repository als Submodul `.ci` einbinden (`git submodule add <url> .ci`) und die Scripts aus `templates/composer.check.json` in die `composer.json` übernehmen. Danach `composer check`.
3. **php-cs-fixer lokal:** `php-cs-fixer-v3.phar` (von `https://cs.symfony.com/download/php-cs-fixer-v3.phar`) ins Modul legen (nicht committen) oder über die Umgebungsvariable `PHP_CS_FIXER` auf eine vorhandene Installation zeigen.

## Versionen

- Module rufen den Workflow mit `@v1` auf. Der Tag `v1` wird bewusst auf neue, kompatible Stände weitergeschoben. Das Skript wird in der CI ebenfalls über `ci-ref` (Standard `v1`) geladen.
- Inkompatible Änderungen erscheinen als `v2`. Module stellen dann bewusst um.
- Lokal ist das Submodul `.ci` auf einen Commit gepinnt. Aktualisieren mit `git submodule update --remote .ci`.

## Herkunft

Orientiert an `Burki24/Symcon_ModuleCI` (MIT) und der offiziellen Style-Action `symcon/action-style`. Dieses Repository führt deren Prüfbefehle direkt aus und hängt nicht von diesen Repositories ab.
