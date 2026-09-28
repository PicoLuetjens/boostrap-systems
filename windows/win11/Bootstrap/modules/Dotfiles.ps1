# ------------------------------------------------------------
# Dotfiles-Modul
#
# Klont (oder aktualisiert) das Dotfiles-Repo und kopiert die
# Konfigurationsdateien an ihre Zielorte. Gesteuert über
# config\dotfiles.json.
#
# Modi pro Eintrag:
#   copy        (Standard) Datei oder kompletten Ordner kopieren.
#               Geänderte Zieldateien werden vorher als *.bak
#               gesichert, identische Dateien übersprungen.
#   merge-json  JSON-Datei in eine bestehende JSON-Datei mergen
#               (für LibreWolf policies.json).
# ------------------------------------------------------------

function Resolve-DotfilePath {
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ClonePath = ""
    )

    # Documents über die Shell-API ermitteln, weil der Ordner
    # z. B. durch OneDrive umgeleitet sein kann
    $tokens = @{
        "{UserProfile}"  = $env:USERPROFILE
        "{LocalAppData}" = [Environment]::GetFolderPath("LocalApplicationData")
        "{AppData}"      = [Environment]::GetFolderPath("ApplicationData")
        "{Documents}"    = [Environment]::GetFolderPath("MyDocuments")
        "{ProgramFiles}" = $env:ProgramFiles
        "{ClonePath}"    = $ClonePath
    }

    foreach ($key in $tokens.Keys) {
        $Path = $Path.Replace($key, $tokens[$key])
    }

    return $Path
}

function Copy-DotfileFile {
    param (
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $targetDir = Split-Path -Parent $Target

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (Test-Path $Target) {
        $sourceHash = (Get-FileHash -Path $Source -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -Path $Target -Algorithm SHA256).Hash

        if ($sourceHash -eq $targetHash) {
            return "unchanged"
        }

        Copy-Item -Path $Target -Destination "$Target.bak" -Force
        Copy-Item -Path $Source -Destination $Target -Force
        return "updated"
    }

    Copy-Item -Path $Source -Destination $Target -Force
    return "created"
}

function Copy-DotfileItem {
    param (
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $stats = @{ created = 0; updated = 0; unchanged = 0 }

    if (Test-Path $Source -PathType Leaf) {
        $state = Copy-DotfileFile -Source $Source -Target $Target
        $stats[$state]++
        return $stats
    }

    # Ordner: jede Datei einzeln kopieren (Struktur bleibt erhalten)
    $sourceRoot = (Get-Item -Path $Source).FullName.TrimEnd('\', '/')

    foreach ($file in Get-ChildItem -Path $sourceRoot -Recurse -File -Force) {
        $relative   = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $targetFile = Join-Path $Target $relative

        $state = Copy-DotfileFile -Source $file.FullName -Target $targetFile
        $stats[$state]++
    }

    return $stats
}

function Merge-JsonObject {
    # --------------------------------------------------------
    # Merged $Override rekursiv in $Base:
    #   - Objekte werden zusammengeführt
    #   - Arrays werden vereinigt (ohne Duplikate)
    #   - sonst gewinnt der Wert aus $Override
    # --------------------------------------------------------
    param (
        [Parameter(Mandatory)]
        $Base,

        [Parameter(Mandatory)]
        $Override
    )

    foreach ($prop in $Override.PSObject.Properties) {
        $existing = $Base.PSObject.Properties[$prop.Name]

        if ($null -eq $existing) {
            $Base | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            continue
        }

        $baseIsObject     = $existing.Value -is [System.Management.Automation.PSCustomObject]
        $overrideIsObject = $prop.Value -is [System.Management.Automation.PSCustomObject]

        if ($baseIsObject -and $overrideIsObject) {
            Merge-JsonObject -Base $existing.Value -Override $prop.Value | Out-Null
        }
        elseif ($existing.Value -is [array] -and $prop.Value -is [array]) {
            $merged = [System.Collections.Generic.List[object]]::new()
            $seen   = @{}

            foreach ($entry in @($existing.Value) + @($prop.Value)) {
                $key = $entry | ConvertTo-Json -Depth 20 -Compress
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $merged.Add($entry)
                }
            }

            $existing.Value = $merged.ToArray()
        }
        else {
            $existing.Value = $prop.Value
        }
    }

    return $Base
}

function Merge-DotfileJson {
    param (
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $override = Get-Content -Path $Source -Raw -Encoding UTF8 | ConvertFrom-Json

    $targetDir = Split-Path -Parent $Target
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $base = $null

    if (Test-Path $Target) {
        # Original einmalig sichern (z. B. LibreWolf-Standard)
        if (-not (Test-Path "$Target.orig")) {
            Copy-Item -Path $Target -Destination "$Target.orig" -Force
            Write-Log "Original gesichert: $Target.orig"
        }

        try {
            $base = Get-Content -Path $Target -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Log "Bestehende JSON nicht lesbar, wird ersetzt: $Target" -Level Warning
            $base = $null
        }
    }

    if ($null -eq $base) {
        $result = $override
    }
    else {
        $result = Merge-JsonObject -Base $base -Override $override
    }

    $json = $result | ConvertTo-Json -Depth 20

    # UTF-8 ohne BOM schreiben (Firefox/LibreWolf erwartet reines JSON)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Target, $json, $utf8NoBom)
}

function Sync-DotfilesRepository {
    param (
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$ClonePath
    )

    if (Test-Path (Join-Path $ClonePath ".git")) {
        Write-Log "Dotfiles-Repo vorhanden, aktualisiere: $ClonePath"

        git -C $ClonePath pull --ff-only | Out-Host

        if ($LASTEXITCODE -ne 0) {
            Write-Log "git pull fehlgeschlagen (lokale Änderungen?). Verwende vorhandenen Stand." -Level Warning
        }
    }
    elseif (Test-Path $ClonePath) {
        throw "Zielordner existiert, ist aber kein Git-Repo: $ClonePath"
    }
    else {
        Write-Log "Klone Dotfiles-Repo nach: $ClonePath"

        git clone $Repository $ClonePath | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "git clone fehlgeschlagen. Exit Code: $LASTEXITCODE"
        }
    }

    # Das Repo wurde mit Adminrechten geklont und gehört daher der
    # Gruppe "Administratoren". Ohne diesen Eintrag meldet git in einer
    # normalen Shell später "detected dubious ownership".
    $safePath = $ClonePath -replace '\\', '/'
    $safeDirs = @(git config --global --get-all safe.directory 2>$null)

    if ($safeDirs -notcontains $safePath) {
        git config --global --add safe.directory $safePath
        Write-Log "safe.directory für Dotfiles-Repo gesetzt"
    }
}

function Set-UserExecutionPolicy {
    # --------------------------------------------------------
    # Ohne RemoteSigned lädt Windows PowerShell das Profil nicht
    # (Standard auf Windows-Clients ist "Restricted").
    # --------------------------------------------------------

    $current = Get-ExecutionPolicy -Scope CurrentUser

    if ($current -in @("RemoteSigned", "Unrestricted", "Bypass")) {
        Write-Log "ExecutionPolicy (CurrentUser) bereits: $current"
        return
    }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    }
    catch {
        # Tritt auf, wenn z. B. -Scope Process Bypass aktiv ist.
        # Die Einstellung wird trotzdem gespeichert.
    }

    if ((Get-ExecutionPolicy -Scope CurrentUser) -eq "RemoteSigned") {
        Write-Log "ExecutionPolicy (CurrentUser) auf RemoteSigned gesetzt" -Level Success
    }
    else {
        Write-Log "ExecutionPolicy konnte nicht gesetzt werden (Gruppenrichtlinie?)" -Level Warning
    }
}

function Install-Dotfiles {
    param (
        [Parameter(Mandatory)]
        [string]$ConfigFile
    )

    # git schreibt Fortschritt auf stderr.
    # Fehler werden über $LASTEXITCODE geprüft.
    $ErrorActionPreference = "Continue"

    Write-Log "Dotfiles-Installation gestartet"

    # --------------------------------------------------------
    # Konfiguration laden
    # --------------------------------------------------------

    if (-not (Test-Path $ConfigFile)) {
        throw "Konfigurationsdatei nicht gefunden: $ConfigFile"
    }

    try {
        $config = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON konnte nicht gelesen werden: $($_.Exception.Message)"
    }

    # --------------------------------------------------------
    # git prüfen (wurde evtl. gerade erst per Winget installiert)
    # --------------------------------------------------------

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        if (Get-Command Update-EnvironmentPath -ErrorAction SilentlyContinue) {
            Update-EnvironmentPath
        }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git wurde nicht gefunden."
    }

    # --------------------------------------------------------
    # Repo klonen / aktualisieren
    # --------------------------------------------------------

    $clonePath = Resolve-DotfilePath -Path $config.clonePath

    Sync-DotfilesRepository -Repository $config.repository -ClonePath $clonePath

    # --------------------------------------------------------
    # Dateien verteilen
    # --------------------------------------------------------

    $failed = 0

    foreach ($item in $config.items) {

        $source = Join-Path $clonePath $item.source
        $target = Resolve-DotfilePath -Path $item.target -ClonePath $clonePath
        $mode   = if ($item.mode) { $item.mode } else { "copy" }

        if ($item.requires) {
            $required = Resolve-DotfilePath -Path $item.requires -ClonePath $clonePath
            if (-not (Test-Path $required)) {
                Write-Log "$($item.name) übersprungen, nicht gefunden: $required" -Level Warning
                continue
            }
        }

        if (-not (Test-Path $source)) {
            Write-Log "$($item.name): Quelle fehlt im Repo: $($item.source)" -Level Error
            $failed++
            continue
        }

        try {
            switch ($mode) {
                "copy" {
                    $stats = Copy-DotfileItem -Source $source -Target $target
                    Write-Log ("{0} -> {1} ({2} neu, {3} aktualisiert, {4} unverändert)" -f `
                        $item.name, $target, $stats.created, $stats.updated, $stats.unchanged) -Level Success
                }
                "merge-json" {
                    Merge-DotfileJson -Source $source -Target $target
                    Write-Log "$($item.name) -> $target (gemerged)" -Level Success
                }
                default {
                    throw "Unbekannter Modus: $mode"
                }
            }
        }
        catch {
            Write-Log "$($item.name) fehlgeschlagen: $($_.Exception.Message)" -Level Error
            $failed++
        }
    }

    # --------------------------------------------------------
    # PowerShell-Profil ausführbar machen
    # --------------------------------------------------------

    Set-UserExecutionPolicy

    # --------------------------------------------------------
    # Manuelle Schritte anzeigen
    # --------------------------------------------------------

    foreach ($step in $config.manual) {
        $text = Resolve-DotfilePath -Path $step -ClonePath $clonePath
        Write-Log "Manuell: $text" -Level Warning
    }

    if ($failed -gt 0) {
        throw "$failed Dotfile-Einträge fehlgeschlagen"
    }

    Write-Log "Dotfiles-Installation abgeschlossen" -Level Success
}
