#!/usr/bin/env bash
# ------------------------------------------------------------
# Package-Manager-Modul (Gegenstück zu PackageManager.ps1)
# (kompatibel mit der macOS-Standard-Bash 3.2)
#
# Installiert Node.js über Volta und Python 3.14 über uv.
# ------------------------------------------------------------

update_environment_path() {
    # --------------------------------------------------------
    # PATH der aktuellen Session um Homebrew, Volta und
    # ~/.local/bin ergänzen. Dauerhaft setzt das die .zshrc aus
    # den Dotfiles, das gilt aber erst für neue Shells.
    # --------------------------------------------------------

    if declare -F load_brew_env > /dev/null; then
        load_brew_env > /dev/null 2>&1
    fi

    export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"

    local dir
    for dir in "$VOLTA_HOME/bin" "$HOME/.local/bin"; do
        if [[ ":$PATH:" != *":$dir:"* ]]; then
            export PATH="$dir:$PATH"
        fi
    done

    hash -r
    write_log "PATH der aktuellen Session aktualisiert"
}

install_package_manager_tools() {

    write_log "Package Manager Installationen gestartet"

    # --------------------------------------------------------
    # PATH aktualisieren (statt Shell-Neustart)
    # --------------------------------------------------------

    update_environment_path

    # --------------------------------------------------------
    # Volta
    # --------------------------------------------------------

    if ! command -v volta > /dev/null; then
        write_log "Volta wurde nicht gefunden." error
        return 1
    fi

    write_log "Volta gefunden" success
    write_log "Installiere Node.js über Volta"

    if ! volta install node; then
        write_log "volta install node fehlgeschlagen" error
        return 1
    fi

    write_log "Node.js erfolgreich über Volta installiert" success

    # --------------------------------------------------------
    # uv
    # --------------------------------------------------------

    if ! command -v uv > /dev/null; then
        write_log "uv wurde nicht gefunden." error
        return 1
    fi

    write_log "uv gefunden" success
    write_log "Installiere Python 3.14 über uv"

    if ! uv python install 3.14; then
        write_log "uv python install 3.14 fehlgeschlagen" error
        return 1
    fi

    write_log "Python 3.14 erfolgreich über uv installiert" success

    write_log "Package Manager Installationen abgeschlossen" success
}
