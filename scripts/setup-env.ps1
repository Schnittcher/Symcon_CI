<#
.SYNOPSIS
  Richtet die lokale Entwicklungsumgebung fuer Symcon-Module ein oder prueft sie.

.DESCRIPTION
  Legt unter -Root (Standard C:\Symcon-Entwicklung) PHP, php-cs-fixer, PHPUnit, Composer und die Wrapper an.
  Vorhandenes wird erkannt und nicht neu geladen (ausser mit -Update). Das Skript ist wiederholbar.
  Mit -Check wird nur geprueft und nichts veraendert (Exitcode 0 = vollstaendig, 1 = es fehlt etwas).

  Quellen:
    PHP          https://windows.php.net/downloads/releases/   (SHA-256 aus releases.json geprueft)
    Composer     https://getcomposer.org/download/latest-stable/ (SHA-256 geprueft)
    php-cs-fixer https://cs.symfony.com/download/php-cs-fixer-v3.phar (keine Pruefsumme veroeffentlicht)
    PHPUnit      https://phar.phpunit.de/phpunit-<Version>.phar (keine Pruefsumme veroeffentlicht)

.PARAMETER Root
  Zielordner der Umgebung.
.PARAMETER CiPath
  Arbeitskopie von Symcon_CI (fuer den Wrapper symcon-check). Standard: der Ordner ueber diesem Skript.
.PARAMETER PhpMinor
  PHP-Hauptversion, zum Beispiel 8.5.
.PARAMETER PhpUnitMajor
  PHPUnit-Hauptversion, zum Beispiel 13.
.PARAMETER Check
  Nur pruefen, nichts aendern.
.PARAMETER NoPath
  Den Benutzer-Pfad (PATH) nicht veraendern.
.PARAMETER RemoveFromPath
  Eintraege, die dabei aus dem Benutzer-Pfad entfernt werden (zum Beispiel ein frueherer Tools-Ordner).
.PARAMETER Update
  Vorhandene Komponenten neu laden.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Symcon-Entwicklung',
    [string]$CiPath = '',
    [string]$PhpMinor = '8.5',
    [string]$PhpUnitMajor = '13',
    [switch]$Check,
    [switch]$NoPath,
    [string[]]$RemoveFromPath = @(),
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($CiPath -eq '') { $CiPath = Split-Path -Parent $PSScriptRoot }

$phpDir = Join-Path $Root 'php'
$phpExe = Join-Path $phpDir 'php.exe'
$tmp = Join-Path $env:TEMP 'symcon-setup'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$components = @(
    @{ Name = 'PHP'; Path = $phpExe },
    @{ Name = 'php.ini'; Path = (Join-Path $phpDir 'php.ini') },
    @{ Name = 'php-cs-fixer'; Path = (Join-Path $Root 'php-cs-fixer-v3.phar') },
    @{ Name = 'PHPUnit'; Path = (Join-Path $Root 'phpunit.phar') },
    @{ Name = 'Composer'; Path = (Join-Path $Root 'composer.phar') },
    @{ Name = 'php.bat'; Path = (Join-Path $Root 'php.bat') },
    @{ Name = 'php-cs-fixer.bat'; Path = (Join-Path $Root 'php-cs-fixer.bat') },
    @{ Name = 'phpunit.bat'; Path = (Join-Path $Root 'phpunit.bat') },
    @{ Name = 'composer.bat'; Path = (Join-Path $Root 'composer.bat') },
    @{ Name = 'symcon-check.bat'; Path = (Join-Path $Root 'symcon-check.bat') }
)

function Get-Missing {
    return @($components | Where-Object { -not (Test-Path -LiteralPath $_.Path) })
}

function Get-PhpVersion {
    if (-not (Test-Path -LiteralPath $phpExe)) { return '' }
    try { return (& $phpExe -r 'echo PHP_VERSION;') } catch { return '' }
}

function Step([string]$text) { Write-Host "[Setup] $text" }

function Save-Download([string]$url, [string]$target) {
    Step "Lade $url"
    Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
}

function Assert-Hash([string]$file, [string]$expected) {
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) {
        throw "SHA-256 stimmt nicht: $file (erwartet $expected, ist $actual)"
    }
    Step "SHA-256 geprueft: $(Split-Path -Leaf $file)"
}

# ----- Pruefen -----
$missing = Get-Missing
$phpVersion = Get-PhpVersion
$phpOk = $phpVersion -ne '' -and $phpVersion.StartsWith($PhpMinor + '.')

if ($Check) {
    Write-Host "Entwicklungsumgebung: $Root"
    foreach ($c in $components) {
        $state = if (Test-Path -LiteralPath $c.Path) { 'ok' } else { 'FEHLT' }
        Write-Host ('  {0,-20} {1}' -f $c.Name, $state)
    }
    $phpText = if ($phpVersion -eq '') { 'nicht vorhanden' } else { $phpVersion }
    Write-Host "  PHP-Version          $phpText (erwartet $PhpMinor.x)"
    if ($missing.Count -eq 0 -and $phpOk) { Write-Host 'Ergebnis: vollstaendig'; exit 0 }
    Write-Host 'Ergebnis: unvollstaendig, Setup ohne -Check ausfuehren'
    exit 1
}

New-Item -ItemType Directory -Force -Path $Root, $tmp | Out-Null

# ----- PHP -----
if ($Update -or -not $phpOk) {
    $releases = Invoke-RestMethod 'https://windows.php.net/downloads/releases/releases.json'
    $entry = $releases.$PhpMinor
    if ($null -eq $entry) { throw "PHP $PhpMinor nicht in releases.json gefunden" }
    $build = $entry.'nts-vs17-x64'
    if ($null -eq $build) { throw 'Kein NTS-Build (vs17, x64) gefunden' }
    $zipName = $build.zip.path
    $zipFile = Join-Path $tmp $zipName
    Save-Download ('https://windows.php.net/downloads/releases/' + $zipName) $zipFile
    Assert-Hash $zipFile $build.zip.sha256

    $oldIni = Join-Path $phpDir 'php.ini'
    $keepIni = $null
    if (Test-Path -LiteralPath $oldIni) { $keepIni = Get-Content -LiteralPath $oldIni -Raw }

    $extract = Join-Path $tmp 'php-extract'
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    Expand-Archive -LiteralPath $zipFile -DestinationPath $extract -Force
    if (Test-Path -LiteralPath $phpDir) { Remove-Item -LiteralPath $phpDir -Recurse -Force }
    Move-Item -LiteralPath $extract -Destination $phpDir

    if ($null -ne $keepIni) {
        [IO.File]::WriteAllText($oldIni, $keepIni, $utf8NoBom)
        Step 'Bestehende php.ini uebernommen'
    }
}

$ini = Join-Path $phpDir 'php.ini'
if (-not (Test-Path -LiteralPath $ini)) {
    $text = Get-Content -LiteralPath (Join-Path $phpDir 'php.ini-development') -Raw
    $text = $text -replace '(?m)^;\s*extension_dir\s*=\s*"ext"', 'extension_dir = "ext"'
    foreach ($e in 'curl', 'fileinfo', 'mbstring', 'openssl', 'zip') {
        $text = $text -replace "(?m)^;\s*extension=$e\s*$", "extension=$e"
    }
    [IO.File]::WriteAllText($ini, $text, $utf8NoBom)
    Step 'php.ini angelegt (curl, fileinfo, mbstring, openssl, zip aktiv)'
}

# ----- Composer -----
$composer = Join-Path $Root 'composer.phar'
if ($Update -or -not (Test-Path -LiteralPath $composer)) {
    $dl = Join-Path $tmp 'composer.phar'
    Save-Download 'https://getcomposer.org/download/latest-stable/composer.phar' $dl
    $sumLine = (Invoke-WebRequest -Uri 'https://getcomposer.org/download/latest-stable/composer.phar.sha256sum' -UseBasicParsing).Content
    $sum = ($sumLine.Trim() -split '\s+')[0]
    Assert-Hash $dl $sum
    Copy-Item -LiteralPath $dl -Destination $composer -Force
}

# ----- php-cs-fixer -----
$fixer = Join-Path $Root 'php-cs-fixer-v3.phar'
if ($Update -or -not (Test-Path -LiteralPath $fixer)) {
    Save-Download 'https://cs.symfony.com/download/php-cs-fixer-v3.phar' $fixer
    Step 'Hinweis: fuer php-cs-fixer gibt es keine veroeffentlichte Pruefsumme.'
}

# ----- PHPUnit -----
$phpunit = Join-Path $Root 'phpunit.phar'
if ($Update -or -not (Test-Path -LiteralPath $phpunit)) {
    Save-Download ('https://phar.phpunit.de/phpunit-' + $PhpUnitMajor + '.phar') $phpunit
    Step 'Hinweis: fuer PHPUnit gibt es nur eine GPG-Signatur, keine Pruefsumme (Signatur nicht geprueft).'
}

# ----- Wrapper -----
function Write-Bat([string]$name, [string]$content) {
    $file = Join-Path $Root $name
    [IO.File]::WriteAllText($file, $content + "`r`n", (New-Object System.Text.ASCIIEncoding))
}
Write-Bat 'php.bat' '@"%~dp0php\php.exe" %*'
Write-Bat 'composer.bat' '@"%~dp0php\php.exe" "%~dp0composer.phar" %*'
Write-Bat 'phpunit.bat' '@"%~dp0php\php.exe" "%~dp0phpunit.phar" %*'
Write-Bat 'php-cs-fixer.bat' ("@set PHP_CS_FIXER_IGNORE_ENV=1`r`n" + '@"%~dp0php\php.exe" "%~dp0php-cs-fixer-v3.phar" %*')
Write-Bat 'symcon-check.bat' ('@"%~dp0php\php.exe" "' + (Join-Path $CiPath 'scripts\check.php') + '" %*')
Step "Wrapper geschrieben (symcon-check zeigt auf $CiPath)"

# ----- Benutzer-Pfad -----
if (-not $NoPath) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $remove = @($RemoveFromPath | ForEach-Object { $_.TrimEnd('\').ToLower() })
    $parts = @($user -split ';' | Where-Object { $_ -ne '' })
    $kept = @($parts | Where-Object { $remove -notcontains $_.TrimEnd('\').ToLower() })
    $rootNorm = $Root.TrimEnd('\').ToLower()
    if (@($kept | Where-Object { $_.TrimEnd('\').ToLower() -eq $rootNorm }).Count -eq 0) { $kept += $Root }
    $newPath = ($kept -join ';')
    if ($newPath -ne $user) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Step "Benutzer-Pfad aktualisiert (neue Terminals noetig): $Root ist enthalten"
    } else {
        Step 'Benutzer-Pfad war bereits korrekt'
    }
}

# ----- Aufraeumen und Zusammenfassung -----
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }

Write-Host ''
Write-Host "Entwicklungsumgebung fertig: $Root"
Write-Host ('  PHP           ' + (Get-PhpVersion))
Write-Host ('  php-cs-fixer  ' + ((& $phpExe $fixer --version 2>&1 | Select-Object -First 1)))
Write-Host ('  PHPUnit       ' + ((& $phpExe $phpunit --version 2>&1 | Select-Object -First 1)))
Write-Host ('  Composer      ' + ((& $phpExe $composer --version 2>&1 | Select-Object -First 1)))
exit 0
