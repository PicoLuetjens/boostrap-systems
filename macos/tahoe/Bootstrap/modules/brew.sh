#!/usr/bin/env bash
# ------------------------------------------------------------
# Software-Modul (Gegenstück zu Winget.ps1 / apt.sh)
# (kompatibel mit der macOS-Standard-Bash 3.2)
#
# Installiert Homebrew (falls nötig) und danach alles aus
# config/software.json. Unterstützte Typen:
#   brew    Homebrew-Formeln (Kommandozeilenprogramme)
#   cask    Homebrew-Casks (Programme mit Oberfläche, Schriften)
#   script  offizielles Installationsskript (als Benutzer)
#   git     Git-Repo klonen (z. B. zsh-Themes und -Plugins)
#
# Gemeinsame optionale Felder:
#   check       Befehl, der nach der Installation existieren muss
#   check_path  Pfad, der nach der Installation existieren muss.
#               Bei Casks: existiert der Pfad schon (z. B. eine
#               von Hand installierte App), wird übersprungen.
#   env / args  nur bei script
#
# Platzhalter in Werten: {home}
# ------------------------------------------------------------

SOFTWARE_INSTALLED=()
SOFTWARE_SKIPPED=()
SOFTWARE_FAILED=()
RELOGIN_REQUIRED=false

# Keine automatischen Updates / Hinweise bei jedem brew-Aufruf
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1

# ------------------------------------------------------------
# Hilfsfunktionen
# ------------------------------------------------------------

# Pfad zu brew (Apple Silicon: /opt/homebrew, Intel: /usr/local)
find_brew() {
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Homebrew-Umgebung (PATH usw.) in die aktuelle Session laden
load_brew_env() {
    local brew_bin
    brew_bin="$(find_brew)" || return 1
    eval "$("$brew_bin" shellenv)"
}

resolve_software_value() {
    local value="$1"
    value="${value//\{home\}/$HOME}"
    printf '%s' "$value"
}

# Liest ein Feld aus dem Eintrag und ersetzt Platzhalter
field() {
    local item="$1"
    local name="$2"
    local raw
    raw="$(jq -r ".$name // empty" <<< "$item")"
    [[ -z "$raw" ]] && return 0
    resolve_software_value "$raw"
}

# Liest ein JSON-Array in eine Variable (Ersatz für mapfile)
# Verwendung: read_json_array "$item" packages PACKAGES
read_json_array() {
    local item="$1"
    local name="$2"
    local target="$3"
    local line
    eval "$target=()"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        eval "$target+=(\"\$line\")"
    done < <(jq -r ".${name}[]? // empty" <<< "$item")
}

# Prüft check / check_path eines Eintrags (0 = vorhanden)
is_present() {
    local item="$1"
    local check check_path
    check="$(jq -r '.check // empty' <<< "$item")"
    check_path="$(field "$item" check_path)"

    [[ -z "$check" && -z "$check_path" ]] && return 1
    [[ -n "$check" ]] && ! command -v "$check" > /dev/null && return 1
    [[ -n "$check_path" && ! -e "$check_path" ]] && return 1
    return 0
}

download() {
    local url="$1"
    local target="$2"
    curl -fsSL --retry 3 -o "$target" "$url"
}

refresh_path() {
    if declare -F update_environment_path > /dev/null; then
        update_environment_path > /dev/null 2>&1
    fi
}

# ------------------------------------------------------------
# Homebrew installieren (falls nötig) + jq als Voraussetzung
# ------------------------------------------------------------

ensure_homebrew() {
    if find_brew > /dev/null; then
        write_log "Homebrew gefunden: $(find_brew)" success
    else
        write_log "Homebrew nicht gefunden, installiere (inkl. Xcode Command Line Tools)"

        local tmp_script
        tmp_script="$(mktemp)"
        download "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$tmp_script" || {
            rm -f "$tmp_script"
            return 1
        }

        # NONINTERACTIVE: keine Rückfragen (sudo ist bereits aktiv)
        NONINTERACTIVE=1 /bin/bash "$tmp_script"
        local rc=$?
        rm -f "$tmp_script"

        if [[ $rc -ne 0 ]] || ! find_brew > /dev/null; then
            write_log "Homebrew-Installation fehlgeschlagen" error
            return 1
        fi

        write_log "Homebrew installiert" success
    fi

    load_brew_env || return 1

    write_log "Aktualisiere Homebrew"
    brew update --quiet || write_log "brew update fehlgeschlagen, fahre fort" warning

    # jq wird zum Lesen der JSON-Konfiguration gebraucht
    if ! command -v jq > /dev/null; then
        brew install jq || return 1
    fi
}

# ------------------------------------------------------------
# Installer pro Typ
# Rückgabe: 0 = installiert, 1 = Fehler, 2 = bereits vorhanden
# ------------------------------------------------------------

install_type_brew() {
    local item="$1"
    local PACKAGES
    read_json_array "$item" packages PACKAGES

    local missing=() pkg
    for pkg in "${PACKAGES[@]}"; do
        brew list --formula --versions "$pkg" > /dev/null 2>&1 || missing+=("$pkg")
    done

    [[ ${#missing[@]} -eq 0 ]] && return 2

    brew install "${missing[@]}"
}

install_type_cask() {
    local item="$1"

    # Von Hand installierte App (z. B. /Applications/iTerm.app)?
    local check_path
    check_path="$(field "$item" check_path)"
    [[ -n "$check_path" && -e "$check_path" ]] && return 2

    local PACKAGES
    read_json_array "$item" packages PACKAGES

    local missing=() pkg
    for pkg in "${PACKAGES[@]}"; do
        brew list --cask --versions "$pkg" > /dev/null 2>&1 || missing+=("$pkg")
    done

    [[ ${#missing[@]} -eq 0 ]] && return 2

    brew install --cask "${missing[@]}"
}

install_type_script() {
    local item="$1"
    is_present "$item" && return 2

    local url
    url="$(field "$item" url)"

    local ARGS
    read_json_array "$item" args ARGS
    local i=0
    while [[ $i -lt ${#ARGS[@]} ]]; do
        ARGS[$i]="$(resolve_software_value "${ARGS[$i]}")"
        i=$((i + 1))
    done

    # Umgebungsvariablen für das Skript
    local env_vars=()
    local key value
    while IFS=$'\t' read -r key value; do
        [[ -z "$key" ]] && continue
        env_vars+=("$key=$(resolve_software_value "$value")")
    done < <(jq -r '.env // {} | to_entries[] | "\(.key)\t\(.value)"' <<< "$item")

    mkdir -p "$HOME/.local/bin"

    local tmp_script
    tmp_script="$(mktemp)"
    download "$url" "$tmp_script" || { rm -f "$tmp_script"; return 1; }

    # ${arr[@]+...}: leere Arrays sind unter "set -u" in Bash 3.2 sonst ein Fehler
    env ${env_vars[@]+"${env_vars[@]}"} bash "$tmp_script" ${ARGS[@]+"${ARGS[@]}"}
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}

install_type_git() {
    local item="$1"
    local url dest
    url="$(field "$item" url)"
    dest="$(field "$item" dest)"

    [[ -d "$dest/.git" ]] && return 2

    mkdir -p "$(dirname "$dest")"
    git clone --depth=1 "$url" "$dest"
}

# ------------------------------------------------------------
# Hauptfunktion
# ------------------------------------------------------------

install_software_from_json() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        write_log "Konfigurationsdatei nicht gefunden: $config_file" error
        return 1
    fi

    ensure_homebrew || {
        write_log "Homebrew konnte nicht eingerichtet werden" error
        return 1
    }

    write_log "Lade Software-Konfiguration"

    if ! jq -e '.software' "$config_file" > /dev/null 2>&1; then
        write_log "JSON konnte nicht gelesen werden oder enthält keine Software" error
        return 1
    fi

    refresh_path

    # --------------------------------------------------------
    # Software durchlaufen
    # (Lesen über fd 3, damit brew/Skripte nicht die
    #  Schleifeneingabe verbrauchen)
    # --------------------------------------------------------

    local item name type rc
    while IFS= read -r item <&3; do
        name="$(jq -r '.name' <<< "$item")"
        type="$(jq -r '.type' <<< "$item")"

        write_log "Prüfe: $name"

        case "$type" in
            brew)   install_type_brew   "$item" < /dev/null ;;
            cask)   install_type_cask   "$item" < /dev/null ;;
            script) install_type_script "$item" < /dev/null ;;
            git)    install_type_git    "$item" < /dev/null ;;
            *)
                write_log "$name: unbekannter Typ '$type'" error
                SOFTWARE_FAILED+=("$name")
                continue
                ;;
        esac
        rc=$?

        [[ $rc -eq 0 ]] && refresh_path

        # Nachprüfung: manche Installskripte melden Erfolg, obwohl
        # nichts installiert wurde
        if [[ $rc -eq 0 ]] && jq -e '.check // .check_path' <<< "$item" > /dev/null &&
                ! is_present "$item"; then
            write_log "$name: nach der Installation nicht gefunden" error
            rc=1
        fi

        case $rc in
            0)
                write_log "$name erfolgreich installiert" success
                SOFTWARE_INSTALLED+=("$name")
                ;;
            2)
                write_log "$name bereits installiert" success
                SOFTWARE_SKIPPED+=("$name")
                ;;
            *)
                write_log "Installation fehlgeschlagen: $name (Exit Code: $rc)" error
                SOFTWARE_FAILED+=("$name")
                ;;
        esac
    done 3< <(jq -c '.software[]' "$config_file")

    write_log "Software fertig: ${#SOFTWARE_INSTALLED[@]} installiert, ${#SOFTWARE_SKIPPED[@]} übersprungen, ${#SOFTWARE_FAILED[@]} fehlgeschlagen"

    return 0
}
