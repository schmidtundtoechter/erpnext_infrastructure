#!/bin/bash

# quickCleanup.sh
# Sehr einfacher Docker Image Cleanup mit Docker's eingebauten Befehlen

set -euo pipefail

FORCE_DELETE=false

# Parse Argumente
while getopts "fh" opt; do
    case $opt in
        f) FORCE_DELETE=true ;;
        h) echo "Usage: $0 [-f] [-h]"; echo "  -f: Tatsächlich löschen"; echo "  -h: Hilfe"; exit 0 ;;
        *) echo "Invalid option. Use -h for help"; exit 1 ;;
    esac
done

# Prüfe Docker
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker ist nicht verfügbar"
    exit 1
fi

echo "📦 Docker Image Cleanup"
echo "   🎯 Modus: $(if [[ $FORCE_DELETE == true ]]; then echo "🗑️ LÖSCHEN"; else echo "💭 SIMULATION"; fi)"
echo ""

# Zeige aktuelle Situation
echo "📊 Docker Status:"
total_images=$(docker images -q | wc -l | tr -d ' ')
dangling_images=$(docker images --filter "dangling=true" -q | wc -l | tr -d ' ')
echo "   📦 Total: $total_images Images ($dangling_images dangling)"

# Docker System info (inkl. Build Cache)
docker system df || true
echo ""

# Prüfe was docker image prune machen würde
if [[ $FORCE_DELETE == true ]]; then
    echo "🗑️ Entferne Dangling Images:"
    docker image prune -f
    echo ""
    
    echo "🗑️ Entferne Build Cache:"
    docker builder prune -a -f
    echo ""
    
    echo "🔍 Nach dem Cleanup:"
    total_after=$(docker images -q | wc -l | tr -d ' ')
    echo "   📦 Verbleibende Images: $total_after"
    docker system df || true
else
    echo "💭 SIMULATION - Was würde gelöscht:"
    echo ""
    echo "🗑️ Dangling Images (würden gelöscht):"
    if [[ $dangling_images -gt 0 ]]; then
        docker images --filter "dangling=true" --format "   🔸 {{.ID}} {{.Size}}"
    else
        echo "   ✅ Keine Dangling Images"
    fi
    echo ""
    
    echo "🗑️ Build Cache (würde gelöscht):"
    docker builder du 2>/dev/null || echo "   ℹ️  Build Cache Info nicht verfügbar"
    echo ""
    
    echo "💡 Für tatsächliches Löschen: $0 -f"
    echo "💡 Für Docker's eigenes Cleanup:"
    echo "   docker image prune -f        # Nur Dangling Images"
    echo "   docker image prune -a -f     # Alle unbenutzten Images"
    echo "   docker builder prune -a -f   # Build Cache"
    echo "   docker system prune -a -f    # Komplettes Cleanup"
fi

echo ""
echo "🎉 Fertig!"