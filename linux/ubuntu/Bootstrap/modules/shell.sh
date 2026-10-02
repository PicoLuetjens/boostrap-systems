#!/usr/bin/env bash
# ------------------------------------------------------------
# Shell-Modul (nur Linux)
#
# Setzt zsh als Standard-Shell des Benutzers. Oh My Zsh,
# Powerlevel10k und die Plugins installiert das Software-Modul,
# die .zshrc kommt aus den Dotfiles.
# ------------------------------------------------------------

configure_shell() {

    write_log "Shell-Konfiguration gestartet"

    local zsh_path
    zsh_path="$(command -v zsh)"

    if [[ -z "$zsh_path" ]]; then
        write_log "zsh wurde nicht gefunden." error
        return 1
    fi

    # zsh muss in /etc/shells stehen, sonst lehnt chsh sie ab
    if ! grep -qx "$zsh_path" /etc/shells; then
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi

    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        write_log "zsh ist bereits Standard-Shell" success
    else
        if ! sudo chsh -s "$zsh_path" "$USER"; then
            write_log "Standard-Shell konnte nicht geändert werden" error
            return 1
        fi

        write_log "Standard-Shell auf zsh geändert ($current_shell -> $zsh_path)" success
        RELOGIN_REQUIRED=true
    fi

    write_log "Shell-Konfiguration abgeschlossen" success
}
