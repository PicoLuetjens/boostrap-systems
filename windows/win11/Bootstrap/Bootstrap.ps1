#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Administratorrechte prüfen
# ------------------------------------------------------------

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity

if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
    Write-Host ""
    Write-Host "[ERROR] Administratorrechte erforderlich." -ForegroundColor Red
    Write-Host "        Bitte PowerShell als Administrator starten." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ------------------------------------------------------------
# Pfade
# ------------------------------------------------------------

$Root           = $PSScriptRoot
$ConfigFile     = Join-Path $Root "config\software.json"
$DotfilesConfig = Join-Path $Root "config\dotfiles.json"
$LogFolder      = Join-Path $Root "logs"

# ------------------------------------------------------------
# Module laden
# ------------------------------------------------------------

. (Join-Path $Root "modules\Logging.ps1")
. (Join-Path $Root "modules\Winget.ps1")
. (Join-Path $Root "modules\PackageManager.ps1")
. (Join-Path $Root "modules\Dotfiles.ps1")

# ------------------------------------------------------------
# Logging starten
# ------------------------------------------------------------

Initialize-Logging -LogDirectory $LogFolder

Write-Log "Bootstrap gestartet" -Level Info
Write-Log "Computer: $env:COMPUTERNAME" -Level Info
Write-Log "Benutzer: $env:USERNAME" -Level Info

try {
    # --------------------------------------------------------
    # Software installieren (Winget)
    # --------------------------------------------------------

    $wingetResult = Install-SoftwareFromJson -ConfigFile $ConfigFile

    # --------------------------------------------------------
    # Node.js (Volta) und Python (uv) installieren
    # --------------------------------------------------------

    Install-PackageManagerTools

    # --------------------------------------------------------
    # Dotfiles klonen und verteilen
    # --------------------------------------------------------

    Install-Dotfiles -ConfigFile $DotfilesConfig

    # Weitere Module können hier ergänzt werden:
    #
    # Configure-Windows
    # Install-WindowsFeatures
    # Configure-Registry

    # --------------------------------------------------------
    # Zusammenfassung
    # --------------------------------------------------------

    if ($wingetResult.RebootRequired) {
        Write-Log "Mindestens ein Paket benötigt einen Neustart." -Level Warning
    }

    if ($wingetResult.Failed.Count -gt 0) {
        Write-Log "Bootstrap mit Fehlern abgeschlossen. Fehlgeschlagen:" -Level Warning
        foreach ($name in $wingetResult.Failed) {
            Write-Log "  - $name" -Level Warning
        }
        exit 1
    }

    Write-Log "Bootstrap erfolgreich abgeschlossen" -Level Success
    exit 0
}
catch {
    Write-Log "Bootstrap fehlgeschlagen" -Level Error
    Write-Log $_.Exception.Message -Level Error
    Write-Log $_.ScriptStackTrace -Level Error
    exit 1
}
