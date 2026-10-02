#!/usr/bin/env bash
# ------------------------------------------------------------
# Dotfiles-Modul (Gegenstück zu Dotfiles.ps1)
# (kompatibel mit der macOS-Standard-Bash 3.2)
#
# Klont (oder aktualisiert) das Dotfiles-Repo und kopiert die
# Konfigurationsdateien an ihre Zielorte. Gesteuert über
# config/dotfiles.json.
#
# Felder pro Eintrag:
#   source    Pfad im Repo (Datei oder Ordner)
#   target    Zielpfad (Platzhalter siehe resolve_dotfile_path)
#   mode      copy (Standard) oder merge-json
#   base      nur merge-json: Grundlage für den Merge (sonst das
#             bestehende Ziel)
#   sudo      true, wenn das Ziel Root-Rechte braucht
#   requires  nur ausführen, wenn dieser Pfad existiert
#   optional  true: fehlende Quelle ist kein Fehler
# ------------------------------------------------------------

resolve_dotfile_path() {
    local path="$1"
    local clone_path="${2:-}"

    path="${path//\{Home\}/$HOME}"
    path="${path//\{ConfigHome\}/${XDG_CONFIG_HOME:-$HOME/.config}}"
    path="${path//\{AppSupport\}/$HOME/Library/Application Support}"
    path="${path//\{ClonePath\}/$clone_path}"
    printf '%s' "$path"
}

# Führt einen Befehl mit oder ohne sudo aus
run_as() {
    local use_sudo="$1"
    shift
    if [[ "$use_sudo" == "true" ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Rückgabe über stdout: created | updated | unchanged
copy_dotfile_file() {
    local source="$1"
    local target="$2"
    local use_sudo="$3"

    run_as "$use_sudo" mkdir -p "$(dirname "$target")"

    if [[ -f "$target" ]]; then
        if cmp -s "$source" "$target"; then
            echo "unchanged"
            return 0
        fi

        run_as "$use_sudo" cp -f "$target" "$target.bak"
        run_as "$use_sudo" cp -f "$source" "$target" || return 1
        echo "updated"
        return 0
    fi

    run_as "$use_sudo" cp -f "$source" "$target" || return 1
    echo "created"
}

# Rückgabe über stdout: "<neu> <aktualisiert> <unverändert>"
copy_dotfile_item() {
    local source="$1"
    local target="$2"
    local use_sudo="$3"

    local created=0 updated=0 unchanged=0 state

    if [[ -f "$source" ]]; then
        state="$(copy_dotfile_file "$source" "$target" "$use_sudo")" || return 1
        case "$state" in
            created)   created=1 ;;
            updated)   updated=1 ;;
            unchanged) unchanged=1 ;;
        esac
        echo "$created $updated $unchanged"
        return 0
    fi

    # Ordner: jede Datei einzeln kopieren (Struktur bleibt erhalten)
    local file relative
    while IFS= read -r -d '' file; do
        relative="${file#"$source"/}"
        state="$(copy_dotfile_file "$file" "$target/$relative" "$use_sudo")" || return 1
        case "$state" in
            created)   created=$((created + 1)) ;;
            updated)   updated=$((updated + 1)) ;;
            unchanged) unchanged=$((unchanged + 1)) ;;
        esac
    done < <(find "$source" -type f -print0)

    echo "$created $updated $unchanged"
}

# --------------------------------------------------------
# JSON rekursiv mergen:
#   - Objekte werden zusammengeführt
#   - Arrays werden vereinigt (ohne Duplikate)
#   - sonst gewinnt der Wert aus der Quelle
# --------------------------------------------------------
JQ_DEEP_MERGE='
def merge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k ($a;
      .[$k] = (if has($k) then merge(.[$k]; $b[$k]) else $b[$k] end))
  elif ($a | type) == "array" and ($b | type) == "array" then
    reduce $b[] as $e ($a; if any(.[]; . == $e) then . else . + [$e] end)
  else
    $b
  end;
merge($base[0]; $override[0])
'

merge_dotfile_json() {
    local source="$1"
    local target="$2"
    local use_sudo="$3"
    local base="${4:-}"

    run_as "$use_sudo" mkdir -p "$(dirname "$target")"

    # Grundlage: explizite Basisdatei, sonst das bestehende Ziel
    if [[ -z "$base" ]]; then
        base="$target"

        # Original einmalig sichern
        if [[ -f "$target" && ! -f "$target.orig" ]]; then
            run_as "$use_sudo" cp "$target" "$target.orig"
            write_log "Original gesichert: $target.orig"
        fi
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -f "$base" ]]; then
        if ! jq -n --slurpfile base "$base" --slurpfile override "$source" \
                "$JQ_DEEP_MERGE" > "$tmp_file" 2>/dev/null; then
            write_log "Basis-JSON nicht lesbar, verwende nur Quelle: $base" warning
            jq . "$source" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
        fi
    else
        jq . "$source" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    fi

    run_as "$use_sudo" install -m 0644 "$tmp_file" "$target"
    local rc=$?
    rm -f "$tmp_file"
    return $rc
}

sync_dotfiles_repository() {
    local repository="$1"
    local clone_path="$2"

    if [[ -d "$clone_path/.git" ]]; then
        write_log "Dotfiles-Repo vorhanden, aktualisiere: $clone_path"

        if ! git -C "$clone_path" pull --ff-only; then
            write_log "git pull fehlgeschlagen (lokale Änderungen?). Verwende vorhandenen Stand." warning
        fi
    elif [[ -e "$clone_path" ]]; then
        write_log "Zielordner existiert, ist aber kein Git-Repo: $clone_path" error
        return 1
    else
        write_log "Klone Dotfiles-Repo nach: $clone_path"

        if ! git clone "$repository" "$clone_path"; then
            write_log "git clone fehlgeschlagen" error
            return 1
        fi
    fi
}

install_dotfiles() {
    local config_file="$1"

    write_log "Dotfiles-Installation gestartet"

    # --------------------------------------------------------
    # Konfiguration laden
    # --------------------------------------------------------

    if [[ ! -f "$config_file" ]]; then
        write_log "Konfigurationsdatei nicht gefunden: $config_file" error
        return 1
    fi

    if ! jq -e '.items' "$config_file" > /dev/null 2>&1; then
        write_log "JSON konnte nicht gelesen werden: $config_file" error
        return 1
    fi

    if ! command -v git > /dev/null; then
        write_log "git wurde nicht gefunden." error
        return 1
    fi

    # --------------------------------------------------------
    # Repo klonen / aktualisieren
    # --------------------------------------------------------

    local repository clone_path
    repository="$(jq -r '.repository' "$config_file")"
    clone_path="$(resolve_dotfile_path "$(jq -r '.clonePath' "$config_file")")"

    sync_dotfiles_repository "$repository" "$clone_path" < /dev/null || return 1

    # --------------------------------------------------------
    # Dateien verteilen
    # --------------------------------------------------------

    local failed=0
    local item name source target mode use_sudo requires optional base stats

    while IFS= read -r item <&3; do
        name="$(jq -r '.name' <<< "$item")"
        source="$clone_path/$(jq -r '.source' <<< "$item")"
        target="$(resolve_dotfile_path "$(jq -r '.target' <<< "$item")" "$clone_path")"
        mode="$(jq -r '.mode // "copy"' <<< "$item")"
        use_sudo="$(jq -r '.sudo // false' <<< "$item")"
        requires="$(jq -r '.requires // empty' <<< "$item")"
        optional="$(jq -r '.optional // false' <<< "$item")"
        base="$(jq -r '.base // empty' <<< "$item")"
        [[ -n "$base" ]] && base="$(resolve_dotfile_path "$base" "$clone_path")"

        if [[ -n "$requires" ]]; then
            requires="$(resolve_dotfile_path "$requires" "$clone_path")"
            if [[ ! -e "$requires" ]]; then
                write_log "$name übersprungen, nicht gefunden: $requires" warning
                continue
            fi
        fi

        if [[ ! -e "$source" ]]; then
            if [[ "$optional" == "true" ]]; then
                write_log "$name übersprungen, nicht im Repo: $(jq -r '.source' <<< "$item")"
                continue
            fi
            write_log "$name: Quelle fehlt im Repo: $(jq -r '.source' <<< "$item")" error
            failed=$((failed + 1))
            continue
        fi

        case "$mode" in
            copy)
                if stats="$(copy_dotfile_item "$source" "$target" "$use_sudo" < /dev/null)"; then
                    read -r c u n <<< "$stats"
                    write_log "$name -> $target ($c neu, $u aktualisiert, $n unverändert)" success
                else
                    write_log "$name fehlgeschlagen" error
                    failed=$((failed + 1))
                fi
                ;;
            merge-json)
                if merge_dotfile_json "$source" "$target" "$use_sudo" "$base" < /dev/null; then
                    write_log "$name -> $target (gemerged)" success
                else
                    write_log "$name fehlgeschlagen" error
                    failed=$((failed + 1))
                fi
                ;;
            *)
                write_log "$name: unbekannter Modus '$mode'" error
                failed=$((failed + 1))
                ;;
        esac
    done 3< <(jq -c '.items[]' "$config_file")

    # --------------------------------------------------------
    # Manuelle Schritte anzeigen
    # --------------------------------------------------------

    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        write_log "Manuell: $(resolve_dotfile_path "$step" "$clone_path")" warning
    done < <(jq -r '.manual[]? // empty' "$config_file")

    if (( failed > 0 )); then
        write_log "$failed Dotfile-Einträge fehlgeschlagen" error
        return 1
    fi

    write_log "Dotfiles-Installation abgeschlossen" success
}
