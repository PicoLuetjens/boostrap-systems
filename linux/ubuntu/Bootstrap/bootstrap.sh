#!/usr/bin/env bash
# ------------------------------------------------------------
# Ubuntu Bootstrap
#
# Aufruf als normaler Benutzer (NICHT mit sudo):
#   ./bootstrap.sh
# ------------------------------------------------------------

set -uo pipefail

# ------------------------------------------------------------
# Kein Root, sondern normaler Benutzer mit sudo
# (sonst landen Dotfiles, Volta, uv usw. bei root)
# ------------------------------------------------------------

if [[ "$EUID" -eq 0 ]]; then
    echo ""
    echo -e "\033[0;31m[ERROR] Bitte nicht als root / mit sudo starten.\033[0m"
    echo -e "\033[0;33m        Als normaler Benutzer ausführen: ./bootstrap.sh\033[0m"
    echo ""
    exit 1
fi

# ------------------------------------------------------------
# System prüfen
# ------------------------------------------------------------

if [[ "$(. /etc/os-release && echo "$ID")" != "ubuntu" ]]; then
    echo -e "\033[0;33m[WARNING] Kein Ubuntu erkannt, Fortsetzung auf eigene Gefahr.\033[0m"
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo -e "\033[0;31m[ERROR] Nur x86_64 wird unterstützt (Download-URLs in software.json).\033[0m"
    exit 1
fi

# ------------------------------------------------------------
# sudo einmal abfragen und für die Laufzeit aktiv halten
# ------------------------------------------------------------

if ! sudo -v; then
    echo -e "\033[0;31m[ERROR] sudo-Rechte erforderlich.\033[0m"
    exit 1
fi

( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# ------------------------------------------------------------
# Pfade
# ------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$ROOT/config/software.json"
DOTFILES_CONFIG="$ROOT/config/dotfiles.json"
LOG_FOLDER="$ROOT/logs"

# ------------------------------------------------------------
# Module laden
# ------------------------------------------------------------

source "$ROOT/modules/logging.sh"
source "$ROOT/modules/apt.sh"
source "$ROOT/modules/package_manager.sh"
source "$ROOT/modules/dotfiles.sh"
source "$ROOT/modules/shell.sh"

# ------------------------------------------------------------
# Logging starten
# ------------------------------------------------------------

initialize_logging "$LOG_FOLDER"

write_log "Bootstrap gestartet"
write_log "Computer: $(hostname)"
write_log "Benutzer: $USER"

fatal() {
    write_log "Bootstrap fehlgeschlagen" error
    write_log "$1" error
    exit 1
}

# ------------------------------------------------------------
# Software installieren (apt & Co.)
# ------------------------------------------------------------

install_software_from_json "$CONFIG_FILE" ||
    fatal "Software-Installation abgebrochen"

# ------------------------------------------------------------
# Node.js (Volta) und Python (uv) installieren
# ------------------------------------------------------------

install_package_manager_tools ||
    fatal "Package-Manager-Installation abgebrochen"

# ------------------------------------------------------------
# Dotfiles klonen und verteilen
# ------------------------------------------------------------

install_dotfiles "$DOTFILES_CONFIG" ||
    fatal "Dotfiles-Installation abgebrochen"

# ------------------------------------------------------------
# zsh als Standard-Shell setzen
# ------------------------------------------------------------

configure_shell ||
    fatal "Shell-Konfiguration abgebrochen"

# Weitere Module können hier ergänzt werden:
#
# configure_gnome
# configure_system

# ------------------------------------------------------------
# Zusammenfassung
# ------------------------------------------------------------

if [[ "$RELOGIN_REQUIRED" == "true" ]]; then
    write_log "Bitte ab- und wieder anmelden (neue Standard-Shell / Gruppe docker)." warning
fi

if (( ${#SOFTWARE_FAILED[@]} > 0 )); then
    write_log "Bootstrap mit Fehlern abgeschlossen. Fehlgeschlagen:" warning
    for name in "${SOFTWARE_FAILED[@]}"; do
        write_log "  - $name" warning
    done
    exit 1
fi

write_log "Bootstrap erfolgreich abgeschlossen" success
exit 0
