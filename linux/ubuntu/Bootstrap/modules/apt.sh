#!/usr/bin/env bash
# ------------------------------------------------------------
# Software-Modul (Gegenstück zu Winget.ps1)
#
# Installiert alles aus config/software.json. Unterstützte Typen:
#   apt       Pakete aus den Ubuntu-Quellen
#   apt-repo  Externe apt-Quelle (Schlüssel + .sources) + Pakete
#   deb       .deb-Datei herunterladen und über apt installieren
#   archive   .tar.gz entpacken (z. B. nach /opt) + Symlinks
#   binary    einzelne .gz-Binärdatei nach /usr/local/bin
#   font      Schriftarchiv nach ~/.local/share/fonts
#   script    offizielles Installationsskript (als Benutzer)
#   git       Git-Repo klonen (z. B. zsh-Themes und -Plugins)
#
# Gemeinsame optionale Felder:
#   check       Befehl, der nach der Installation existieren muss
#   check_path  Pfad, der nach der Installation existieren muss
#   post        Befehle, die nach einer Neuinstallation laufen
#
# Platzhalter in Werten:
#   {home}                    Home-Verzeichnis
#   {codename}                Ubuntu-Codename (z. B. noble)
#   {latest-tag:owner/repo}   neueste Release-Version auf GitHub
#   {latest-go}               neueste Go-Version (z. B. go1.27.1)
# ------------------------------------------------------------

SOFTWARE_INSTALLED=()
SOFTWARE_SKIPPED=()
SOFTWARE_FAILED=()
RELOGIN_REQUIRED=false

# ------------------------------------------------------------
# Hilfsfunktionen
# ------------------------------------------------------------

apt_update() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -q
}

apt_install() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@"
}

apt_is_installed() {
    local pkg
    for pkg in "$@"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
            grep -q "install ok installed" || return 1
    done
    return 0
}

# Neueste Release-Version eines GitHub-Repos über git-Tags
# (ohne GitHub-API, daher kein API-Limit). Nur reine Versionen
# wie "v1.6.0" oder "15.2.0", ohne "v" zurückgegeben.
latest_git_tag() {
    local repo="$1"
    git ls-remote --tags --refs "https://github.com/$repo" 2>/dev/null |
        awk -F/ '{print $3}' |
        grep -E '^v?[0-9]+(\.[0-9]+)*$' |
        sed 's/^v//' |
        sort -V | tail -1
}

latest_go_version() {
    curl -fsSL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1
}

# Ersetzt alle Platzhalter in einem Wert aus der JSON
resolve_software_value() {
    local value="$1"
    local codename
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

    value="${value//\{home\}/$HOME}"
    value="${value//\{codename\}/$codename}"

    while [[ "$value" =~ \{latest-tag:([^}]+)\} ]]; do
        local tag
        tag="$(latest_git_tag "${BASH_REMATCH[1]}")"
        [[ -z "$tag" ]] && { write_log "Version für ${BASH_REMATCH[1]} nicht ermittelbar" error; return 1; }
        value="${value//"${BASH_REMATCH[0]}"/$tag}"
    done

    if [[ "$value" == *"{latest-go}"* ]]; then
        local go_version
        go_version="$(latest_go_version)"
        [[ -z "$go_version" ]] && { write_log "Go-Version nicht ermittelbar" error; return 1; }
        value="${value//\{latest-go\}/$go_version}"
    fi

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

# Name -> Dateiname, z. B. "Docker Engine" -> "docker-engine"
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//'
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
# Voraussetzungen (werden für das Skript selbst gebraucht)
# ------------------------------------------------------------

install_prerequisites() {
    write_log "Installiere Voraussetzungen (curl, jq, git, ...)"

    apt_update || return 1

    apt_install ca-certificates curl gnupg jq git xz-utils fontconfig debconf-utils || return 1

    # Microsoft-Fonts-EULA vorab akzeptieren. Das Paket wird z. B. von
    # OnlyOffice nachgezogen und würde sonst im unbeaufsichtigten Modus
    # abbrechen und alle weiteren apt-Installationen blockieren.
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" |
        sudo debconf-set-selections
}

# ------------------------------------------------------------
# Installer pro Typ
# Rückgabe: 0 = installiert, 1 = Fehler, 2 = bereits vorhanden
# ------------------------------------------------------------

install_type_apt() {
    local item="$1"
    local packages
    mapfile -t packages < <(jq -r '.packages[]' <<< "$item")

    apt_is_installed "${packages[@]}" && return 2

    apt_install "${packages[@]}"
}

install_type_apt_repo() {
    local item="$1"
    local name slug key_url uris suites components arch
    name="$(jq -r '.name' <<< "$item")"
    slug="$(slugify "$name")"
    key_url="$(field "$item" key)"
    uris="$(field "$item" uris)"
    suites="$(field "$item" suites)"
    components="$(field "$item" components)"
    arch="$(dpkg --print-architecture)"

    local packages
    mapfile -t packages < <(jq -r '.packages[]' <<< "$item")

    local result=2

    if ! apt_is_installed "${packages[@]}"; then
        local keyring="/etc/apt/keyrings/$slug.asc"
        local sources="/etc/apt/sources.list.d/$slug.sources"

        # Schlüssel + Quelle anlegen (bei erneutem Lauf überschrieben)
        sudo install -m 0755 -d /etc/apt/keyrings
        local tmp_key
        tmp_key="$(mktemp)"
        download "$key_url" "$tmp_key" || { rm -f "$tmp_key"; return 1; }
        sudo install -m 0644 "$tmp_key" "$keyring"
        rm -f "$tmp_key"

        sudo tee "$sources" > /dev/null <<EOF
Types: deb
URIs: $uris
Suites: $suites
Components: $components
Architectures: $arch
Signed-By: $keyring
EOF

        apt_update || return 1
        apt_install "${packages[@]}" || return 1
        result=0
    fi

    # Benutzer zu Gruppen hinzufügen (z. B. docker)
    local group
    while IFS= read -r group; do
        [[ -z "$group" ]] && continue
        if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "$group"; then
            sudo usermod -aG "$group" "$USER"
            write_log "Benutzer $USER zur Gruppe '$group' hinzugefügt" warning
            RELOGIN_REQUIRED=true
        fi
    done < <(jq -r '.groups[]? // empty' <<< "$item")

    return $result
}

install_type_deb() {
    local item="$1"
    local package url
    package="$(jq -r '.package' <<< "$item")"

    apt_is_installed "$package" && return 2

    url="$(field "$item" url)" || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    chmod 755 "$tmp_dir"   # apt liest als Benutzer _apt

    if ! download "$url" "$tmp_dir/$package.deb"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    chmod 644 "$tmp_dir/$package.deb"
    apt_install "$tmp_dir/$package.deb"
    local rc=$?
    rm -rf "$tmp_dir"
    return $rc
}

install_type_archive() {
    local item="$1"
    is_present "$item" && return 2

    local url dest strip
    url="$(field "$item" url)" || return 1
    dest="$(field "$item" dest)"
    strip="$(jq -r '.strip // 1' <<< "$item")"

    local tmp_file
    tmp_file="$(mktemp)"
    download "$url" "$tmp_file" || { rm -f "$tmp_file"; return 1; }

    sudo rm -rf "$dest"
    sudo mkdir -p "$dest"
    sudo tar -xzf "$tmp_file" -C "$dest" --strip-components="$strip" || { rm -f "$tmp_file"; return 1; }
    rm -f "$tmp_file"

    # Symlinks anlegen: "Linkpfad": "Pfad im Archiv"
    local link rel
    while IFS=$'\t' read -r link rel; do
        [[ -z "$link" ]] && continue
        sudo mkdir -p "$(dirname "$link")"
        sudo ln -sf "$dest/$rel" "$link"
    done < <(jq -r '.links // {} | to_entries[] | "\(.key)\t\(.value)"' <<< "$item")
}

install_type_binary() {
    local item="$1"
    is_present "$item" && return 2

    local url dest
    url="$(field "$item" url)" || return 1
    dest="$(field "$item" dest)"

    local tmp_file
    tmp_file="$(mktemp)"
    download "$url" "$tmp_file.gz" || { rm -f "$tmp_file" "$tmp_file.gz"; return 1; }
    gunzip -f "$tmp_file.gz" || { rm -f "$tmp_file" "$tmp_file.gz"; return 1; }

    sudo install -m 0755 "$tmp_file" "$dest"
    local rc=$?
    rm -f "$tmp_file"
    return $rc
}

install_type_font() {
    local item="$1"
    local url dest
    dest="$(field "$item" dest)"

    if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        return 2
    fi

    url="$(field "$item" url)" || return 1

    local tmp_file
    tmp_file="$(mktemp)"
    download "$url" "$tmp_file" || { rm -f "$tmp_file"; return 1; }

    mkdir -p "$dest"
    tar -xJf "$tmp_file" -C "$dest" || { rm -f "$tmp_file"; return 1; }
    rm -f "$tmp_file"

    fc-cache -f > /dev/null
}

install_type_script() {
    local item="$1"
    is_present "$item" && return 2

    local url
    url="$(field "$item" url)" || return 1

    local args=()
    local arg
    while IFS= read -r arg; do
        arg="$(resolve_software_value "$arg")" || return 1
        args+=("$arg")
    done < <(jq -r '.args[]? // empty' <<< "$item")

    # Umgebungsvariablen für das Skript (z. B. feste Version)
    local env_vars=()
    local key value
    while IFS=$'\t' read -r key value; do
        [[ -z "$key" ]] && continue
        value="$(resolve_software_value "$value")" || return 1
        env_vars+=("$key=$value")
    done < <(jq -r '.env // {} | to_entries[] | "\(.key)\t\(.value)"' <<< "$item")

    # Manche Skripte erwarten, dass das Zielverzeichnis existiert
    mkdir -p "$HOME/.local/bin"

    local tmp_script
    tmp_script="$(mktemp)"
    download "$url" "$tmp_script" || { rm -f "$tmp_script"; return 1; }

    env "${env_vars[@]}" bash "$tmp_script" "${args[@]}"
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

# Befehle aus "post" ausführen (nur nach Neuinstallation)
run_post_commands() {
    local item="$1"
    local cmd
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        cmd="$(resolve_software_value "$cmd")" || return 1
        bash -c "$cmd" || { write_log "Post-Befehl fehlgeschlagen: $cmd" error; return 1; }
    done < <(jq -r '.post[]? // empty' <<< "$item")
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

    install_prerequisites || {
        write_log "Voraussetzungen konnten nicht installiert werden" error
        return 1
    }

    write_log "Lade Software-Konfiguration"

    if ! jq -e '.software' "$config_file" > /dev/null 2>&1; then
        write_log "JSON konnte nicht gelesen werden oder enthält keine Software" error
        return 1
    fi

    # Bereits installierte Tools (z. B. ~/.local/bin) sichtbar machen
    refresh_path

    # --------------------------------------------------------
    # Software durchlaufen
    # (Lesen über fd 3, damit apt/sudo/Skripte nicht die
    #  Schleifeneingabe verbrauchen)
    # --------------------------------------------------------

    local item name type rc
    while IFS= read -r item <&3; do
        name="$(jq -r '.name' <<< "$item")"
        type="$(jq -r '.type' <<< "$item")"

        write_log "Prüfe: $name"

        case "$type" in
            apt)      install_type_apt      "$item" < /dev/null ;;
            apt-repo) install_type_apt_repo "$item" < /dev/null ;;
            deb)      install_type_deb      "$item" < /dev/null ;;
            archive)  install_type_archive  "$item" < /dev/null ;;
            binary)   install_type_binary   "$item" < /dev/null ;;
            font)     install_type_font     "$item" < /dev/null ;;
            script)   install_type_script   "$item" < /dev/null ;;
            git)      install_type_git      "$item" < /dev/null ;;
            *)
                write_log "$name: unbekannter Typ '$type'" error
                SOFTWARE_FAILED+=("$name")
                continue
                ;;
        esac
        rc=$?

        if [[ $rc -eq 0 ]]; then
            # Frisch installierte Tools für den weiteren Lauf sichtbar machen
            refresh_path

            run_post_commands "$item" < /dev/null || rc=1
        fi

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
