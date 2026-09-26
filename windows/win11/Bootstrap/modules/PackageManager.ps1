function Update-EnvironmentPath {
# --------------------------------------------------------
# PATH aus User- und Machine-Umgebung neu laden.
#
# Das ist wichtig, wenn Volta oder uv während des
# Bootstrap-Vorgangs installiert wurden.
# --------------------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable(
    "Path",
    "User"
)

$machinePath = [Environment]::GetEnvironmentVariable(
    "Path",
    "Machine"
)

$env:Path = "$userPath;$machinePath"

Write-Log "PATH der aktuellen Session aktualisiert"


}

function Install-PackageManagerTools {

Write-Log "Package Manager Installations gestartet"

# --------------------------------------------------------
# PATH aktualisieren
# --------------------------------------------------------

Update-EnvironmentPath

# --------------------------------------------------------
# Volta
# --------------------------------------------------------

if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
    throw "Volta wurde nicht gefunden."
}

Write-Log "Volta gefunden" -Level Success
Write-Log "Installiere Node.js über Volta"

volta install node

if ($LASTEXITCODE -ne 0) {
    throw "volta install node fehlgeschlagen. Exit Code: $LASTEXITCODE"
}

Write-Log "Node.js erfolgreich über Volta installiert" -Level Success

# --------------------------------------------------------
# uv
# --------------------------------------------------------

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv wurde nicht gefunden."
}

Write-Log "uv gefunden" -Level Success
Write-Log "Installiere Python 3.14 über uv"

uv python install 3.14

if ($LASTEXITCODE -ne 0) {
    throw "uv python install 3.14 fehlgeschlagen. Exit Code: $LASTEXITCODE"
}

Write-Log "Python 3.14 erfolgreich über uv installiert" -Level Success

Write-Log "Package Manager Installationen abgeschlossen" -Level Success


}
