$script:LogFile = $null

function Initialize-Logging {
    param (
        [Parameter(Mandatory)]
        [string]$LogDirectory
    )

    # Log-Verzeichnis erstellen
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    $script:LogFile = Join-Path $LogDirectory "bootstrap-$timestamp.log"

    Write-Log "Logging initialisiert: $script:LogFile" -Level Info
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"

    # Text für Logdatei
    $line = "[$timestamp] [$Level] $Message"

    # Ausgabe in Konsole
    $color = switch ($Level) {
        "Info"    { "Gray" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
    }

    Write-Host $line -ForegroundColor $color

    # Ausgabe in Logdatei (explizit UTF-8, sonst schreibt PS 5.1 ANSI)
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
}
