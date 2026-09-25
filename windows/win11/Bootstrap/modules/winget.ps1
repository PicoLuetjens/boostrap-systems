function Install-SoftwareFromJson {
param (
[Parameter(Mandatory)]
[string]$ConfigFile
)

# --------------------------------------------------------
# Konfiguration laden
# --------------------------------------------------------

if (-not (Test-Path $ConfigFile)) {
    throw "Konfigurationsdatei nicht gefunden: $ConfigFile"
}

Write-Log "Lade Software-Konfiguration" -Level Info

try {
    $config = Get-Content -Path $ConfigFile -Raw |
        ConvertFrom-Json
}
catch {
    throw "JSON konnte nicht gelesen werden: $($_.Exception.Message)"
}

if (-not $config.software) {
    Write-Log "Keine Software konfiguriert" -Level Warning
    return
}

# --------------------------------------------------------
# Winget prüfen
# --------------------------------------------------------

$winget = Get-Command winget -ErrorAction SilentlyContinue

if (-not $winget) {
    throw "Winget wurde nicht gefunden"
}

Write-Log "Winget gefunden" -Level Success

# --------------------------------------------------------
# Software durchlaufen
# --------------------------------------------------------

foreach ($software in $config.software) {

    Write-Log "Prüfe: $($software.name)" -Level Info

    # Prüfen, ob bereits installiert
    winget list `
        --id $software.id `
        --exact `
        --accept-source-agreements `
        *> $null

    if ($LASTEXITCODE -eq 0) {
        Write-Log "$($software.name) bereits installiert" -Level Success
        continue
    }

    # ----------------------------------------------------
    # Installation
    # ----------------------------------------------------

    Write-Log "Installiere: $($software.name)" -Level Info

    winget install `
        --id $software.id `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        throw "Installation fehlgeschlagen: $($software.name)"
    }

    Write-Log "$($software.name) erfolgreich installiert" -Level Success
}


}
