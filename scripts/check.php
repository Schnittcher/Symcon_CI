#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Zentrale Prüfung für Symcon-Module. Läuft lokal vor dem Commit und in der CI identisch.
 *
 * Aufruf im Modul-Repository (Arbeitsverzeichnis = Repository-Wurzel):
 *   php <pfad-zu>/check.php [--only=style|tests] [--strict]
 *
 *   --only=style  nur Stilprüfungen: JSON-Syntax, StylePHP (json-check), php-cs-fixer (Workflow style.yml)
 *   --only=tests  nur Tests: PHP-Syntax, PHPUnit (Workflow tests.yml)
 *   --strict      auch übersprungene Prüfungen als Fehler werten
 *
 * Ohne --only laufen beide Gruppen. Schritte: PHP-Syntax, JSON-Syntax, StylePHP (json-check),
 * php-cs-fixer (Prüfmodus), PHPUnit.
 * Exitcode 0 nur, wenn keine Prüfung fehlgeschlagen ist. Übersprungene Prüfungen werden immer ausgegeben.
 */

const STATUS_OK = 'ok';
const STATUS_FAIL = 'FEHLER';
const STATUS_SKIP = 'übersprungen';

const EXCLUDED_DIRS = ['.git', '.style', '.ci', 'vendor', 'node_modules'];
const EXCLUDED_PATHS = ['tests/stubs'];

$options = getopt('', ['only:', 'strict', 'help']);
if (isset($options['help'])) {
    echo "Aufruf: php check.php [--only=style|tests] [--strict]\n";
    exit(0);
}
$only = isset($options['only']) && is_string($options['only']) ? $options['only'] : '';
if (!in_array($only, ['', 'style', 'tests'], true)) {
    fwrite(STDERR, "Ungültiger Wert für --only (erlaubt: style, tests)\n");
    exit(2);
}
$runStyle = $only !== 'tests';
$runTests = $only !== 'style';
$strict = isset($options['strict']);
$root = getcwd();

$results = [];

/**
 * Sammelt Dateien mit der gewünschten Endung unterhalb des Arbeitsverzeichnisses.
 *
 * @return list<string> relative Pfade mit /
 */
function collectFiles(string $root, string $extension): array
{
    $iterator = new RecursiveIteratorIterator(
        new RecursiveCallbackFilterIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            static function (SplFileInfo $file) use ($root): bool {
                $relative = str_replace('\\', '/', substr($file->getPathname(), strlen($root) + 1));
                if ($file->isDir()) {
                    if (in_array($file->getFilename(), EXCLUDED_DIRS, true)) {
                        return false;
                    }
                    foreach (EXCLUDED_PATHS as $excluded) {
                        if ($relative === $excluded) {
                            return false;
                        }
                    }
                }
                return true;
            }
        )
    );

    $files = [];
    foreach ($iterator as $file) {
        if ($file->isFile() && strtolower($file->getExtension()) === $extension) {
            $files[] = str_replace('\\', '/', substr($file->getPathname(), strlen($root) + 1));
        }
    }
    sort($files);
    return $files;
}

/**
 * Führt einen Befehl aus und liefert Exitcode und Ausgabe.
 *
 * @param array<string,string> $env zusätzliche Umgebungsvariablen
 * @return array{0:int,1:string}
 */
function run(string $command, array $env = []): array
{
    $process = proc_open(
        $command,
        [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes,
        null,
        $env === [] ? null : array_merge(getenv(), $env)
    );
    if (!is_resource($process)) {
        return [1, 'Prozess konnte nicht gestartet werden: ' . $command];
    }
    $output = stream_get_contents($pipes[1]) . stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    return [proc_close($process), trim($output)];
}

function php(string $arguments): string
{
    return escapeshellarg(PHP_BINARY) . ' ' . $arguments;
}

function record(array &$results, string $name, string $status, string $detail = ''): void
{
    $results[] = ['name' => $name, 'status' => $status, 'detail' => $detail];
}

// 1. PHP-Syntax
$phpFiles = $runTests ? collectFiles($root, 'php') : [];
$syntaxErrors = [];
foreach ($phpFiles as $file) {
    [$code, $output] = run(php('-l ' . escapeshellarg($file)));
    if ($code !== 0) {
        $syntaxErrors[] = $output;
    }
}
if ($runTests) {
    if ($syntaxErrors === []) {
        record($results, 'PHP-Syntax (php -l)', STATUS_OK, count($phpFiles) . ' Dateien');
    } else {
        record($results, 'PHP-Syntax (php -l)', STATUS_FAIL, implode("\n", $syntaxErrors));
    }
}

// 2. JSON-Syntax
$jsonFiles = $runStyle ? collectFiles($root, 'json') : [];
$jsonErrors = [];
foreach ($jsonFiles as $file) {
    try {
        json_decode((string) file_get_contents($root . '/' . $file), false, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        $jsonErrors[] = $file . ': ' . $exception->getMessage();
    }
}
if ($runStyle) {
    if ($jsonErrors === []) {
        record($results, 'JSON-Syntax', STATUS_OK, count($jsonFiles) . ' Dateien');
    } else {
        record($results, 'JSON-Syntax', STATUS_FAIL, implode("\n", $jsonErrors));
    }
}

// 3. StylePHP: json-check
if ($runStyle && !is_file($root . '/.style/json-check.php')) {
    record($results, 'StylePHP json-check', STATUS_FAIL, '.style/json-check.php fehlt (Submodul .style initialisieren: git submodule update --init)');
} elseif ($runStyle) {
    [$code, $output] = run(php('.style/json-check.php'));
    record($results, 'StylePHP json-check', $code === 0 ? STATUS_OK : STATUS_FAIL, $code === 0 ? '' : $output);
}

// 4. php-cs-fixer im Prüfmodus
if ($runStyle) {
    $config =$root . '/.style/.php-cs-fixer.php';
    $fixer = null;
    $fromEnv = getenv('PHP_CS_FIXER');
    $candidates = [
        is_string($fromEnv) ? $fromEnv : '',
        $root . '/php-cs-fixer-v3.phar',
        // lokale Umgebung (setup-env.ps1): <Root>/php/php.exe neben <Root>/php-cs-fixer-v3.phar
        dirname(PHP_BINARY, 2) . '/php-cs-fixer-v3.phar',
    ];
    foreach ($candidates as $candidate) {
        if ($candidate !== '' && is_file($candidate)) {
            $fixer = $candidate;
            break;
        }
    }
    if (!is_file($config)) {
        record($results, 'php-cs-fixer', STATUS_FAIL, '.style/.php-cs-fixer.php fehlt (Submodul .style initialisieren)');
    } elseif ($fixer === null) {
        record($results, 'php-cs-fixer', STATUS_SKIP, 'nicht gefunden (php-cs-fixer-v3.phar neben dem PHP-Ordner, im Modul oder Umgebungsvariable PHP_CS_FIXER)');
    } else {
        [$code, $output] = run(
            php(escapeshellarg($fixer) . ' fix --config=' . escapeshellarg($config) . ' --dry-run --diff --allow-risky=yes --using-cache=no -v'),
            ['PHP_CS_FIXER_IGNORE_ENV' => '1']
        );
        record($results, 'php-cs-fixer', $code === 0 ? STATUS_OK : STATUS_FAIL, $code === 0 ? '' : $output);
    }
}

// 5. PHPUnit (zentral bereitgestellt: phpunit.phar neben dem PHP-Ordner, Umgebungsvariable PHPUNIT oder phpunit im PATH)
$phpunitCommand = null;
$fromEnv = getenv('PHPUNIT');
foreach ([is_string($fromEnv) ? $fromEnv : '', dirname(PHP_BINARY, 2) . '/phpunit.phar', $root . '/phpunit.phar'] as $candidate) {
    if ($candidate !== '' && is_file($candidate)) {
        $phpunitCommand = php(escapeshellarg($candidate));
        break;
    }
}
if ($phpunitCommand === null) {
    [$whichCode] = run(PHP_OS_FAMILY === 'Windows' ? 'where phpunit' : 'command -v phpunit');
    if ($whichCode === 0) {
        $phpunitCommand = 'phpunit';
    }
}

$phpunitConfig = null;
foreach (['phpunit.xml', 'phpunit.xml.dist', 'tests/phpunit.xml'] as $candidate) {
    if (is_file($root . '/' . $candidate)) {
        $phpunitConfig = $candidate;
        break;
    }
}

if (!$runTests) {
    // PHPUnit gehört zur Gruppe tests und läuft bei --only=style nicht
} elseif (!is_dir($root . '/tests')) {
    record($results, 'PHPUnit', STATUS_SKIP, 'kein Ordner tests/ vorhanden');
} elseif ($phpunitCommand === null) {
    record($results, 'PHPUnit', STATUS_SKIP, 'PHPUnit nicht gefunden (phpunit.phar neben dem PHP-Ordner, Umgebungsvariable PHPUNIT oder phpunit im PATH)');
} elseif ($phpunitConfig !== null) {
    [$code, $output] = run($phpunitCommand . ' --configuration ' . escapeshellarg($phpunitConfig));
    record($results, 'PHPUnit', $code === 0 ? STATUS_OK : STATUS_FAIL, $code === 0 ? '' : $output);
} elseif (is_file($root . '/tests/bootstrap.php')) {
    [$code, $output] = run($phpunitCommand . ' --bootstrap tests/bootstrap.php tests');
    record($results, 'PHPUnit', $code === 0 ? STATUS_OK : STATUS_FAIL, $code === 0 ? '' : $output);
} else {
    record($results, 'PHPUnit', STATUS_SKIP, 'weder phpunit.xml noch tests/bootstrap.php vorhanden');
}

// Ausgabe
$failed = 0;
$skipped = 0;
echo "\nSymcon-Modulprüfung\n";
echo str_repeat('-', 60) . "\n";
foreach ($results as $result) {
    printf("%-28s %s%s\n", $result['name'], $result['status'], $result['status'] === STATUS_OK && $result['detail'] !== '' ? ' (' . $result['detail'] . ')' : '');
    if ($result['status'] !== STATUS_OK && $result['detail'] !== '') {
        echo '    ' . str_replace("\n", "\n    ", $result['detail']) . "\n";
    }
    $failed += $result['status'] === STATUS_FAIL ? 1 : 0;
    $skipped += $result['status'] === STATUS_SKIP ? 1 : 0;
}
echo str_repeat('-', 60) . "\n";
echo sprintf("%d fehlgeschlagen, %d übersprungen\n", $failed, $skipped);

exit($failed > 0 || ($strict && $skipped > 0) ? 1 : 0);
