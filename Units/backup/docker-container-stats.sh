#!/usr/bin/env bash

# Parse Argumente
SORT_BY="name"
REVERSE=""

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Show Docker container statistics with human-readable output.

Options:
    -h          Show this help message
    -t          Sort by time (age)
    -s          Sort by size (SIZE_ROOTFS)
    -w          Sort by write size (SIZE_RW)
    -r          Reverse sort order

Examples:
    $(basename "$0")           # Default: sort by name
    $(basename "$0") -t        # Sort by age
    $(basename "$0") -s -r     # Sort by size (largest first)
    $(basename "$0") -w -r     # Sort by write size (largest first)
EOF
    exit 0
}

while getopts "htswr" opt; do
    case $opt in
        h) show_help ;;
        t) SORT_BY="time" ;;
        s) SORT_BY="size" ;;
        w) SORT_BY="write" ;;
        r) REVERSE="reverse" ;;
        *) show_help ;;
    esac
done

# Temporäre Datei für die Ausgabe
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Header
printf "%-45s %-12s %-8s %-12s %-10s %-10s\n" \
    "NAME" "ID" "STATUS" "AGE" "SIZE_RW" "SIZE_ROOTFS"

# Liste aller Container (auch stopped) und speichere in temp file
docker ps -a --format "{{.ID}}" | while read -r container; do
    
    # Hole Details einzeln, um Tab-Probleme zu vermeiden
    name=$(docker inspect --format "{{.Name}}" "$container" | sed 's/^\/\(.*\)/\1/')
    id=$(docker inspect --format "{{.Id}}" "$container")
    status=$(docker inspect --format "{{.State.Status}}" "$container")
    created=$(docker inspect --format "{{.Created}}" "$container")

    # Hole Size-Informationen separat
    size_info=$(docker ps -a -s --filter "id=${container}" --format "{{.Size}}" | head -n1)

    # Parse size info (format: "SIZE_RW (virtual SIZE_TOTAL)")
    if [[ "$size_info" =~ ^(.+)\ \(virtual\ (.+)\)$ ]]; then
        size_rw_hr="${BASH_REMATCH[1]}"
        size_root_hr="${BASH_REMATCH[2]}"
    else
        size_rw_hr="N/A"
        size_root_hr="N/A"
    fi

    # Berechne relative Zeit (X ago)
    # Konvertiere ISO 8601 zu Epoch - funktioniert sowohl auf Linux als auch macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: verwende date -j -f
        created_clean=$(echo "$created" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$//')
        created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$created_clean" +%s 2>/dev/null || echo 0)
    else
        # Linux: verwende date -d
        created_clean=$(echo "$created" | sed 's/\.[0-9]*Z$/Z/')
        created_epoch=$(date -d "$created_clean" +%s 2>/dev/null || echo 0)
    fi
    now_epoch=$(date +%s)
    age_seconds=$((now_epoch - created_epoch))
    
    if [ $age_seconds -lt 60 ]; then
        age_human="${age_seconds}s ago"
    elif [ $age_seconds -lt 3600 ]; then
        age_human="$((age_seconds / 60))m ago"
    elif [ $age_seconds -lt 86400 ]; then
        age_human="$((age_seconds / 3600))h ago"
    elif [ $age_seconds -lt 604800 ]; then
        age_human="$((age_seconds / 86400))d ago"
    elif [ $age_seconds -lt 2592000 ]; then
        age_human="$((age_seconds / 604800))w ago"
    else
        age_human="$((age_seconds / 2592000))mo ago"
    fi

    # Konvertiere size_root_hr zu Bytes für Sortierung
    size_bytes=0
    if [[ "$size_root_hr" =~ ^([0-9.]+)([KMGT]?B)$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        case "$unit" in
            B) size_bytes=$(echo "$num" | awk '{printf "%.0f", $1}') ;;
            KB) size_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024}') ;;
            MB) size_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024}') ;;
            GB) size_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}') ;;
            TB) size_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024}') ;;
        esac
    fi

    # Konvertiere size_rw_hr zu Bytes für Sortierung
    size_rw_bytes=0
    if [[ "$size_rw_hr" =~ ^([0-9.]+)([KMGT]?B)$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        case "$unit" in
            B) size_rw_bytes=$(echo "$num" | awk '{printf "%.0f", $1}') ;;
            KB) size_rw_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024}') ;;
            MB) size_rw_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024}') ;;
            GB) size_rw_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}') ;;
            TB) size_rw_bytes=$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024}') ;;
        esac
    fi

    # Speichere für Sortierung: epoch|size_bytes|size_rw_bytes|name|id|status|age_human|size_rw|size_root
    echo "${created_epoch}|${size_bytes}|${size_rw_bytes}|${name}|${id:0:12}|${status}|${age_human}|${size_rw_hr}|${size_root_hr}" >> "$TEMP_FILE"
done

# Sortiere basierend auf den Argumenten
if [ "$SORT_BY" = "time" ]; then
    # Bei Zeit: höherer epoch = neuere Container, default newest first
    SORT_CMD="sort -t'|' -k1,1nr"
    [ "$REVERSE" = "reverse" ] && SORT_CMD="sort -t'|' -k1,1n"
elif [ "$SORT_BY" = "size" ]; then
    SORT_CMD="sort -t'|' -k2,2n"
    [ "$REVERSE" = "reverse" ] && SORT_CMD="sort -t'|' -k2,2nr"
elif [ "$SORT_BY" = "write" ]; then
    SORT_CMD="sort -t'|' -k3,3n"
    [ "$REVERSE" = "reverse" ] && SORT_CMD="sort -t'|' -k3,3nr"
else
    # Nach Name sortieren (4. Feld)
    SORT_CMD="sort -t'|' -k4,4"
    [ "$REVERSE" = "reverse" ] && SORT_CMD="sort -t'|' -k4,4r"
fi

# Sortiere und gebe aus
eval "$SORT_CMD" "$TEMP_FILE" | while IFS='|' read -r epoch size_bytes size_rw_bytes name id status age_human size_rw size_root; do
    printf "%-45s %-12s %-8s %-12s %-10s %-10s\n" \
        "$name" "$id" "$status" "$age_human" "$size_rw" "$size_root"
done
