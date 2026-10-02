#!/usr/bin/env bash
# ------------------------------------------------------------
# Logging-Modul
# (kompatibel mit der macOS-Standard-Bash 3.2)
# ------------------------------------------------------------

LOG_FILE=""

initialize_logging() {
    local log_directory="$1"

    mkdir -p "$log_directory"

    LOG_FILE="$log_directory/bootstrap-$(date +%Y-%m-%d_%H-%M-%S).log"
    : > "$LOG_FILE"

    write_log "Logging initialisiert: $LOG_FILE" info
}

# Verwendung: write_log "Nachricht" [info|success|warning|error]
write_log() {
    local message="$1"
    local level="${2:-info}"
    local color label

    case "$level" in
        info)    color="\033[0;37m"; label="Info" ;;
        success) color="\033[0;32m"; label="Success" ;;
        warning) color="\033[0;33m"; label="Warning" ;;
        error)   color="\033[0;31m"; label="Error" ;;
        *)       color="\033[0m";    label="Info" ;;
    esac

    local line
    line="[$(date +%H:%M:%S)] [$label] $message"

    # Ausgabe in Konsole (farbig, auf stderr, damit Rückgabewerte
    # von Funktionen nicht verfälscht werden)
    printf "%b%s\033[0m\n" "$color" "$line" >&2

    # Ausgabe in Logdatei
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$line" >> "$LOG_FILE"
    fi
}
