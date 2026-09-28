function Update-EnvironmentPath {
    # --------------------------------------------------------
    # Umgebungsvariablen aus Machine- und User-Umgebung neu
    # laden (wie eine neue Shell), damit frisch installierte
    # Tools (Volta, uv) sofort verfügbar sind.
    # Reihenfolge wie bei Windows: erst Machine, dann User.
    # --------------------------------------------------------

    # Diese Variablen nicht überschreiben (Machine enthält z. B.
    # USERNAME=SYSTEM)
    $skip = @("Path", "USERNAME", "PROCESSOR_ARCHITECTURE", "PSModulePath")

    foreach ($scope in "Machine", "User") {
        $vars = [Environment]::GetEnvironmentVariables($scope)

        foreach ($name in $vars.Keys) {
            if ($skip -contains $name) { continue }
            Set-Item -Path "Env:$name" -Value $vars[$name]
        }
    }

    # PATH zusammensetzen: Machine + User
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")

    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"

    Write-Log "Umgebungsvariablen der aktuellen Session aktualisiert"
}

function Install-PackageManagerTools {

    # Native Programme (volta, uv) schreiben Fortschritt auf stderr.
    # Fehler werden über $LASTEXITCODE geprüft.
    $ErrorActionPreference = "Continue"

    Write-Log "Package Manager Installationen gestartet"

    # --------------------------------------------------------
    # Umgebungsvariablen neu laden (statt Shell-Neustart)
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

    volta install node | Out-Host

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

    uv python install 3.14 | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "uv python install 3.14 fehlgeschlagen. Exit Code: $LASTEXITCODE"
    }

    Write-Log "Python 3.14 erfolgreich über uv installiert" -Level Success

    Write-Log "Package Manager Installationen abgeschlossen" -Level Success
}
