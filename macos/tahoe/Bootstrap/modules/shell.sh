#!/usr/bin/env bash
# ------------------------------------------------------------
# Shell-Modul (macOS)
# (kompatibel mit der macOS-Standard-Bash 3.2)
#
# - setzt zsh als Standard-Shell (Standard seit macOS 10.15,
#   wird hier nur sichergestellt)
# - setzt das iTerm2-Profil aus den Dotfiles als Standardprofil
#
# Oh My Zsh, Powerlevel10k und die Plugins installiert das
# Software-Modul, .zshrc und iTerm2-Profil kommen aus den Dotfiles.
# ------------------------------------------------------------

ITERM2_DYNAMIC_PROFILE="$HOME/Library/Application Support/iTerm2/DynamicProfiles/pico.json"

configure_default_shell() {
    local zsh_path="/bin/zsh"

    local current_shell
    current_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        write_log "zsh ist bereits Standard-Shell" success
        return 0
    fi

    if ! sudo chsh -s "$zsh_path" "$USER"; then
        write_log "Standard-Shell konnte nicht geändert werden" error
        return 1
    fi

    write_log "Standard-Shell auf zsh geändert (${current_shell:-?} -> $zsh_path)" success
    RELOGIN_REQUIRED=true
}

configure_iterm2() {
    if [[ ! -f "$ITERM2_DYNAMIC_PROFILE" ]]; then
        write_log "iTerm2-Profil nicht gefunden, übersprungen: $ITERM2_DYNAMIC_PROFILE" warning
        return 0
    fi

    local guid
    guid="$(jq -r '.Profiles[0].Guid // empty' "$ITERM2_DYNAMIC_PROFILE")"

    if [[ -z "$guid" ]]; then
        write_log "iTerm2-Profil enthält keine Guid" error
        return 1
    fi

    local current
    current="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"

    if [[ "$current" == "$guid" ]]; then
        write_log "iTerm2-Profil ist bereits Standard" success
        return 0
    fi

    if pgrep -xq iTerm2; then
        write_log "iTerm2 läuft gerade. Standardprofil wird beim nächsten Start übernommen, sonst in iTerm2 unter Settings > Profiles setzen." warning
    fi

    defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
    write_log "iTerm2-Standardprofil gesetzt" success
}

configure_shell() {

    write_log "Shell-Konfiguration gestartet"

    configure_default_shell || return 1
    configure_iterm2 || return 1

    write_log "Shell-Konfiguration abgeschlossen" success
}
