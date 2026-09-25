$script:LogFile = $null

function Initialize-Logging {
param (
[Parameter(Mandatory)]
[string]$LogDirectory
)

# Log-Verzeichnis erstellen
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force |
        Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$script:LogFile = Join-Path `
    $LogDirectory `
    "bootstrap-$timestamp.log"

Write-Log "Logging initialisiert" -Level Info


}

function Write-Log {
param (
[Parameter(Mandatory)]
[string]$Message,

    [ValidateSet("Info", "Success", "Warning", "Error")]
    [string]$Level = "Info"
)

$timestamp = Get-Date -Format "HH:mm:ss"

# Text für Logdatei
$line = "[$timestamp] [$Level] $Message"

# Ausgabe in Konsole
switch ($Level) {
    "Info" {
        $color = "Gray"
    }
    "Success" {
        $color = "Green"
    }
    "Warning" {
        $color = "Yellow"
    }
    "Error" {
        $color = "Red"
    }
}

Write-Host $line -ForegroundColor $color

# Ausgabe in Logdatei
if ($script:LogFile) {
    Add-Content -Path $script:LogFile -Value $line
}


}
