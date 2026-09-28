# ------------------------------------------------------------
# Winget-Exit-Codes, die kein echter Fehler sind
# (als Dezimalzahl, weil PS 5.1 und PS 7 Hex-Literale
#  wie 0x8A150061 unterschiedlich interpretieren)
# ------------------------------------------------------------

$script:WingetOkCodes = @(
    0            # Erfolg
    -1978335135  # 0x8A150061 Paket bereits installiert
    -1978335189  # 0x8A15002B Kein Update verfügbar
)

$script:WingetRebootCodes = @(
    -1978334967  # 0x8A150109 Neustart nötig, um Installation abzuschließen
    -1978334966  # 0x8A15010A Neustart nötig vor Installation
    1641         # MSI: Neustart eingeleitet
    3010         # MSI: Neustart erforderlich
)

function Install-SoftwareFromJson {
    param (
        [Parameter(Mandatory)]
        [string]$ConfigFile
    )

    # Native Programme (winget) sollen nicht durch Ausgaben auf
    # stderr abbrechen. Fehler werden über $LASTEXITCODE geprüft.
    $ErrorActionPreference = "Continue"

    $result = [pscustomobject]@{
        Installed      = [System.Collections.Generic.List[string]]::new()
        Skipped        = [System.Collections.Generic.List[string]]::new()
        Failed         = [System.Collections.Generic.List[string]]::new()
        RebootRequired = $false
    }

    # --------------------------------------------------------
    # Konfiguration laden
    # --------------------------------------------------------

    if (-not (Test-Path $ConfigFile)) {
        throw "Konfigurationsdatei nicht gefunden: $ConfigFile"
    }

    Write-Log "Lade Software-Konfiguration" -Level Info

    try {
        $config = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON konnte nicht gelesen werden: $($_.Exception.Message)"
    }

    if (-not $config.software) {
        Write-Log "Keine Software konfiguriert" -Level Warning
        return $result
    }

    # --------------------------------------------------------
    # Winget prüfen
    # --------------------------------------------------------

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Winget wurde nicht gefunden"
    }

    Write-Log "Winget gefunden" -Level Success

    # --------------------------------------------------------
    # Software durchlaufen
    # --------------------------------------------------------

    foreach ($software in $config.software) {

        Write-Log "Prüfe: $($software.name)" -Level Info

        # Prüfen, ob bereits installiert
        $null = winget list `
            --id $software.id `
            --exact `
            --accept-source-agreements `
            --disable-interactivity 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($software.name) bereits installiert" -Level Success
            $result.Skipped.Add($software.name)
            continue
        }

        # ----------------------------------------------------
        # Installation
        # ----------------------------------------------------

        Write-Log "Installiere: $($software.name)" -Level Info

        winget install `
            --id $software.id `
            --exact `
            --source winget `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity | Out-Host

        # Out-Host: Ausgabe nur anzeigen, nicht als Rückgabewert
        # der Funktion zurückgeben
        $code = $LASTEXITCODE

        if ($script:WingetOkCodes -contains $code) {
            Write-Log "$($software.name) erfolgreich installiert" -Level Success
            $result.Installed.Add($software.name)
        }
        elseif ($script:WingetRebootCodes -contains $code) {
            Write-Log "$($software.name) installiert (Neustart erforderlich)" -Level Warning
            $result.Installed.Add($software.name)
            $result.RebootRequired = $true
        }
        else {
            Write-Log "Installation fehlgeschlagen: $($software.name) (Exit Code: $code)" -Level Error
            $result.Failed.Add($software.name)
        }
    }

    Write-Log ("Winget fertig: {0} installiert, {1} übersprungen, {2} fehlgeschlagen" -f `
        $result.Installed.Count, $result.Skipped.Count, $result.Failed.Count) -Level Info

    return $result
}
