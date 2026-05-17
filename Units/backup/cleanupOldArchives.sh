#!/bin/bash

# cleanupOldArchives.sh
# 🗂️ Intelligente Backup-Löschpolicy: Behalte alle Backups der letzten X Tage,
# danach nur ein Backup pro Monat für Y Monate

set -euo pipefail

# ⚙️ Konfiguration
KEEP_DAYS_DEFAULT=30        # Anzahl Tage für die alle Backups behalten werden
KEEP_MONTHS_DEFAULT=12      # Anzahl Monate für die ein Backup pro Monat behalten wird
FORCE_DELETE=false
DRY_RUN=true

# 📖 Funktion für Hilfe
show_help() {
    cat << EOF
🗂️ Intelligente Backup-Cleanup Policy

Usage: $0 [OPTIONS] [DIRECTORY]

📋 OPTIONEN:
    -d DAYS     📅 Anzahl Tage für die alle Backups behalten werden (default: $KEEP_DAYS_DEFAULT)
    -m MONTHS   📆 Anzahl Monate für die ein Backup pro Monat behalten wird (default: $KEEP_MONTHS_DEFAULT)
    -c COMPONENT 🧩 Nur Backups einer bestimmten Komponente verarbeiten
    -f          🗑️  Dateien tatsächlich löschen (ohne -f nur Simulation)
    -h          ❓ Diese Hilfe anzeigen

📝 BEISPIEL:
    $0 -d 14 -m 6 -f /path/to/backups
    $0 -d 7 -m 3 -c monitoring -f /path/to/backups
    
    ➡️ Behält alle Backups der letzten 14 Tage und ein Backup pro Monat für 6 Monate.
    ➡️ Verarbeitet nur Backups der Komponente 'monitoring' mit anderen Parametern.

🔍 PATTERN:
    Das Skript erkennt Backup-Dateien mit einem der folgenden Patterns:
    Pattern 1: component_YYYYMMDDHHMMSS_description.extension
    Pattern 2: YYYYMMDD_HHMMSS-component-description.extension
    
    📦 Alle Dateien mit demselben Timestamp werden als zusammengehörig betrachtet.

🔧 POLICY:
    ✅ BEHALTEN: Alle Backups der letzten X Tage
    📊 BEHALTEN: Ein Backup pro Monat für Y Monate  
    ❌ LÖSCHEN: Duplicate Backups im selben Monat
    🗑️  LÖSCHEN: Backups älter als Y Monate

EOF
}

# 🔍 Funktion zur Extraktion des Timestamps aus dem Dateinamen
extract_timestamp() {
    local filename="$1"
    # Pattern 1: component_YYYYMMDDHHMMSS_description.extension
    # Extrahiere YYYYMMDDHHMMSS Teil (14 Ziffern)
    if [[ $filename =~ ([0-9]{14}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # Pattern 2: YYYYMMDD_HHMMSS-component-description.extension
    # Extrahiere YYYYMMDD_HHMMSS und konvertiere zu YYYYMMDDHHMMSS
    if [[ $filename =~ ^([0-9]{8})_([0-9]{6})-.*$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        return
    fi
    
    echo ""
}

# 🏷️ Funktion zur Extraktion der Komponente aus dem Dateinamen
extract_component() {
    local filename="$1"
    # Pattern 1: component_YYYYMMDDHHMMSS_description.extension
    # Extrahiere component Teil (alles vor dem ersten Timestamp)
    if [[ $filename =~ ^([^_]+)_[0-9]{14} ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # Pattern 2: YYYYMMDD_HHMMSS-component-description.extension
    # Extrahiere component Teil (zwischen erstem und zweitem Bindestrich)
    if [[ $filename =~ ^[0-9]{8}_[0-9]{6}-([^-]+)-.*$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    echo "unknown"
}

# ⏰ Funktion zur Konvertierung von YYYYMMDDHHMMSS zu Unix-Timestamp
timestamp_to_unix() {
    local ts="$1"
    local date_part="${ts:0:8}"
    local time_part="${ts:8:6}"
    
    local year="${date_part:0:4}"
    local month="${date_part:4:2}"
    local day="${date_part:6:2}"
    local hour="${time_part:0:2}"
    local minute="${time_part:2:2}"
    local second="${time_part:4:2}"
    
    # Erkenne OS und verwende entsprechende date-Implementierung
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$(uname)" == "Darwin" ]]; then
        # macOS date format
        date -j -f "%Y%m%d%H%M%S" "${year}${month}${day}${hour}${minute}${second}" "+%s" 2>/dev/null || echo "0"
    elif command -v gdate >/dev/null 2>&1; then
        # GNU date (falls installiert)
        gdate -d "${year}-${month}-${day} ${hour}:${minute}:${second}" "+%s" 2>/dev/null || echo "0"
    else
        # Linux date (GNU coreutils)
        date -d "${year}-${month}-${day} ${hour}:${minute}:${second}" "+%s" 2>/dev/null || echo "0"
    fi
}

# 📅 Funktion zur plattformübergreifenden Formatierung von Unix-Timestamps
format_unix_timestamp() {
    local unix_ts="$1"
    local format="${2:-+%Y-%m-%d %H:%M:%S}"
    
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$(uname)" == "Darwin" ]]; then
        # macOS date format
        date -r "$unix_ts" "$format" 2>/dev/null || echo "invalid-date"
    else
        # Linux date format
        date -d "@$unix_ts" "$format" 2>/dev/null || echo "invalid-date"
    fi
}

# 💾 Funktion zur Konvertierung von Bytes in menschenlesbare Größen
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    local size="$bytes"
    
    if [[ $bytes -eq 0 ]]; then
        echo "0 B"
        return
    fi
    
    while [[ $size -ge 1024 && $unit -lt 4 ]]; do
        size=$((size / 1024))
        ((unit++))
    done
    
    if [[ $unit -eq 0 ]]; then
        echo "${size} ${units[$unit]}"
    else
        # Berechne präziseren Wert ohne bc
        local remainder=$((bytes))
        local i=0
        while [[ $i -lt $unit ]]; do
            remainder=$((remainder))
            ((i++))
        done
        
        # Für bessere Lesbarkeit: zeige 1-2 Dezimalstellen
        local divisor=1
        local j=0
        while [[ $j -lt $unit ]]; do
            divisor=$((divisor * 1024))
            ((j++))
        done
        
        local whole=$((bytes / divisor))
        local fraction=$(( (bytes * 100 / divisor) % 100 ))
        
        if [[ $fraction -eq 0 ]]; then
            echo "${whole} ${units[$unit]}"
        else
            printf "%d.%02d %s\n" "$whole" "$fraction" "${units[$unit]}"
        fi
    fi
}

# 📊 Funktion zur Analyse und Auswahl der zu behaltenden Backups
analyze_backups() {
    local dir="$1"
    local keep_days="$2"
    local keep_months="$3"
    local target_component="${4:-}"
    
    echo "📁 Analysiere Verzeichnis: $dir"
    if [[ -n "$target_component" ]]; then
        echo "🧩 Filtere nur Komponente: $target_component"
    fi
    
    # Aktuelle Zeit
    local now=$(date "+%s")
    local cutoff_recent=$((now - keep_days * 86400))
    local cutoff_old=$((now - keep_months * 30 * 86400))
    
    # 📂 Temporäre Dateien für Datensammlung
    local temp_dir=$(mktemp -d)
    local backup_data="$temp_dir/backup_data"
    local monthly_keeps="$temp_dir/monthly_keeps"
    
    # 🔍 Sammle alle Backup-Dateien mit Timestamps
    # Format: timestamp|unix_timestamp|component|filepath
    while IFS= read -r -d '' file; do
        local basename=$(basename "$file")
        local ts=$(extract_timestamp "$basename")
        local component=$(extract_component "$basename")
        
        # 🧩 Filtere nach Komponente falls angegeben
        if [[ -n "$target_component" && "$component" != "$target_component" ]]; then
            continue
        fi
        
        if [[ -n "$ts" ]]; then
            local unix_ts=$(timestamp_to_unix "$ts")
            if [[ $unix_ts -gt 0 ]]; then
                echo "$ts|$unix_ts|$component|$file" >> "$backup_data"
            fi
        fi
    done < <(find "$dir" -maxdepth 1 -type f -print0)
    
    if [[ ! -f "$backup_data" ]] || [[ ! -s "$backup_data" ]]; then
        echo "⚠️  Keine Backup-Dateien mit erkennbarem Timestamp-Pattern gefunden."
        if [[ -n "${temp_dir:-}" ]] && [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir"
        fi
        return
    fi
    
    # 📋 Sortiere nach Timestamp (neueste zuerst) und entferne Duplikate
    sort -t'|' -k2,2nr "$backup_data" | sort -t'|' -k1,1 -u > "$backup_data.sorted"
    
    local total_timestamps=$(cut -d'|' -f1 "$backup_data.sorted" | sort -u | wc -l | tr -d ' ')
    echo "📦 Gefunden: $total_timestamps verschiedene Backup-Zeitpunkte"
    
    # 🎯 Bestimme welche Backups behalten werden sollen
    local deleted_count=0
    local kept_count=0
    
    # 🔄 Verarbeite jeden einzigartigen Timestamp
    cut -d'|' -f1 "$backup_data.sorted" | sort -u | while read -r ts; do
        local unix_ts=$(grep "^$ts|" "$backup_data.sorted" | head -1 | cut -d'|' -f2)
        local keep_backup=false
        
        # 📅 Prüfe ob Backup innerhalb der "keep all" Periode liegt
        if [[ $unix_ts -ge $cutoff_recent ]]; then
            keep_backup=true
            echo "✅ BEHALTEN (recent): $ts ($(format_unix_timestamp $unix_ts '+%Y-%m-%d %H:%M:%S'))"
        elif [[ $unix_ts -ge $cutoff_old ]]; then
            # 📊 Für ältere Backups: nur eins pro Komponente pro Monat behalten
            local year_month=$(format_unix_timestamp "$unix_ts" "+%Y-%m")
            
            # Sammle alle Komponenten für diesen Timestamp
            local components=($(grep "^$ts|" "$backup_data" | cut -d'|' -f3 | sort -u))
            
            for component in "${components[@]}"; do
                local component_month_key="${component}_${year_month}"
                
                if ! grep -q "^$component_month_key$" "$monthly_keeps" 2>/dev/null; then
                    # Erstes (neuestes) Backup dieser Komponente in diesem Monat behalten
                    echo "$component_month_key" >> "$monthly_keeps"
                    echo "📊 BEHALTEN (monthly): $ts ($(format_unix_timestamp $unix_ts '+%Y-%m-%d %H:%M:%S')) - $component in $year_month"
                    
                    # Alle Dateien dieser Komponente mit diesem Timestamp behalten
                    grep "^$ts|.*|$component|" "$backup_data" | while IFS='|' read -r file_ts file_unix_ts file_component file_path; do
                        echo "   💾 BEHALTEN: $file_path"
                        echo "KEEP:$file_path" >> "$temp_dir/keep_files"
                    done
                else
                    echo "🔄 LÖSCHEN (monthly duplicate): $ts ($(format_unix_timestamp $unix_ts '+%Y-%m-%d %H:%M:%S')) - $component in $year_month"
                    
                    # Alle Dateien dieser Komponente mit diesem Timestamp löschen
                    grep "^$ts|.*|$component|" "$backup_data" | while IFS='|' read -r file_ts file_unix_ts file_component file_path; do
                        if [[ $FORCE_DELETE == true ]]; then
                            echo "   🗑️  LÖSCHE: $file_path"
                            rm -f "$file_path"
                        else
                            echo "   💭 WÜRDE LÖSCHEN: $file_path"
                        fi
                        echo "DELETE:$file_path" >> "$temp_dir/delete_files"
                    done
                fi
            done
            continue
        else
            echo "�🗑️  LÖSCHEN (too old): $ts ($(format_unix_timestamp $unix_ts '+%Y-%m-%d %H:%M:%S'))"
        fi
        
        # 📁 Verarbeite alle Dateien mit diesem Timestamp (für recent und too old)
        if [[ $keep_backup == true ]]; then
            # Recent files - alle behalten
            grep "^$ts|" "$backup_data" | while IFS='|' read -r file_ts file_unix_ts file_component file_path; do
                echo "   💾 BEHALTEN: $file_path"
                echo "KEEP:$file_path" >> "$temp_dir/keep_files"
            done
        elif [[ $unix_ts -lt $cutoff_old ]]; then
            # Too old files - alle löschen
            grep "^$ts|" "$backup_data" | while IFS='|' read -r file_ts file_unix_ts file_component file_path; do
                if [[ $FORCE_DELETE == true ]]; then
                    echo "   🗑️  LÖSCHE: $file_path"
                    rm -f "$file_path"
                else
                    echo "   💭 WÜRDE LÖSCHEN: $file_path"
                fi
                echo "DELETE:$file_path" >> "$temp_dir/delete_files"
            done
        fi
        
    done
    
    # Zähle die Ergebnisse
    local kept_count=0
    local deleted_count=0
    local total_size_to_delete=0
    local total_size_to_keep=0
    
    if [[ -f "$temp_dir/keep_files" ]]; then
        kept_count=$(wc -l < "$temp_dir/keep_files")
        # Berechne Größe der zu behaltenden Dateien
        while IFS= read -r file_path; do
            file_path=${file_path#KEEP:}
            if [[ -f "$file_path" ]]; then
                local file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
                total_size_to_keep=$((total_size_to_keep + file_size))
            fi
        done < "$temp_dir/keep_files"
    fi
    
    if [[ -f "$temp_dir/delete_files" ]]; then
        deleted_count=$(wc -l < "$temp_dir/delete_files")
        # Berechne Größe der zu löschenden Dateien
        while IFS= read -r file_path; do
            file_path=${file_path#DELETE:}
            if [[ -f "$file_path" ]]; then
                local file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
                total_size_to_delete=$((total_size_to_delete + file_size))
            fi
        done < "$temp_dir/delete_files"
    fi
    
    echo ""
    echo "📊 Zusammenfassung für $dir:"
    echo "   ✅ Dateien behalten: $kept_count ($(format_bytes $total_size_to_keep))"
    echo "   🗑️  Dateien gelöscht: $deleted_count ($(format_bytes $total_size_to_delete))"
    if [[ $total_size_to_delete -gt 0 ]]; then
        echo "   💾 Freizugebender Speicherplatz: $(format_bytes $total_size_to_delete)"
    fi
    
    # 💽 Festplatten-Status anzeigen
    local disk_info=$(df -h "$dir" | tail -1)
    local filesystem=$(echo "$disk_info" | awk '{print $1}')
    local size=$(echo "$disk_info" | awk '{print $2}')
    local used=$(echo "$disk_info" | awk '{print $3}')
    local available=$(echo "$disk_info" | awk '{print $4}')
    local usage_percent=$(echo "$disk_info" | awk '{print $5}')
    
    echo "   💽 Festplatte: $filesystem ($size gesamt, $used belegt, $available frei, $usage_percent voll)"
    echo ""
    
    # 🧹 Cleanup
    if [[ -n "${temp_dir:-}" ]] && [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
    fi
}

# 🚀 Hauptfunktion
main() {
    local keep_days="$KEEP_DAYS_DEFAULT"
    local keep_months="$KEEP_MONTHS_DEFAULT"
    local target_dir="."
    local target_component=""
    
    # 🔧 Parse Kommandozeilenargumente
    while getopts "d:m:c:fh" opt; do
        case $opt in
            d)
                keep_days="$OPTARG"
                if ! [[ "$keep_days" =~ ^[0-9]+$ ]]; then
                    echo "❌ Error: -d erwartet eine positive Zahl" >&2
                    exit 1
                fi
                ;;
            m)
                keep_months="$OPTARG"
                if ! [[ "$keep_months" =~ ^[0-9]+$ ]]; then
                    echo "❌ Error: -m erwartet eine positive Zahl" >&2
                    exit 1
                fi
                ;;
            c)
                target_component="$OPTARG"
                ;;
            f)
                FORCE_DELETE=true
                DRY_RUN=false
                ;;
            h)
                show_help
                exit 0
                ;;
            \?)
                echo "❌ Invalid option: -$OPTARG" >&2
                echo "💡 Use -h for help" >&2
                exit 1
                ;;
        esac
    done
    
    shift $((OPTIND-1))
    
    # 📂 Setze Zielverzeichnis falls angegeben
    if [[ $# -gt 0 ]]; then
        target_dir="$1"
    fi
    
    # ✅ Prüfe ob Verzeichnis existiert
    if [[ ! -d "$target_dir" ]]; then
        echo "❌ Error: Verzeichnis '$target_dir' existiert nicht." >&2
        exit 1
    fi
    
    echo "🗂️  Backup-Cleanup Policy:"
    echo "   📅 Behalte alle Backups der letzten $keep_days Tage"
    echo "   📆 Behalte ein Backup pro Monat für $keep_months Monate"
    echo "   🎯 Modus: $(if [[ $FORCE_DELETE == true ]]; then echo "🗑️  LÖSCHEN"; else echo "💭 SIMULATION"; fi)"
    echo "   📁 Verzeichnis: $target_dir"
    if [[ -n "$target_component" ]]; then
        echo "   🧩 Komponente: $target_component"
    fi
    echo ""
    
    if [[ $DRY_RUN == true ]]; then
        echo "⚠️  WARNUNG: Simulation-Modus! Verwende -f um tatsächlich zu löschen."
        echo ""
    fi
    
    # 🔄 Verarbeite Zielverzeichnis
    analyze_backups "$target_dir" "$keep_days" "$keep_months" "$target_component"
    
    # 📁 Verarbeite Unterverzeichnisse rekursiv
    while IFS= read -r -d '' subdir; do
        if [[ "$subdir" != "$target_dir" ]]; then
            analyze_backups "$subdir" "$keep_days" "$keep_months" "$target_component"
        fi
    done < <(find "$target_dir" -type d -print0)
    
    echo "🎉 Cleanup abgeschlossen!"
}

# 🚀 Skript ausführen
main "$@"