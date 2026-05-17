#!/bin/bash

echo "=== Docker Speicher Übersicht ==="
echo ""

echo "Gesamtgröße /var/lib/docker/overlay2:"
du -sh /var/lib/docker/overlay2 2>/dev/null || echo "  Nicht verfügbar (Remote-Zugriff)"
echo ""

# Hole docker system df Output
SYS_DF=$(docker system df)

echo "1. Images:"
img_count=$(docker images -q | wc -l | tr -d ' ')
img_line=$(echo "$SYS_DF" | grep "Images")
img_size=$(echo "$img_line" | awk '{print $4}')
img_reclaim=$(echo "$img_line" | awk '{print $5}')
echo "   Anzahl: $img_count Images"
echo "   Größe: $img_size (davon $img_reclaim aufräumbar)"

# Liste reclaimable Images auf (dangling + unused)
echo "   Reclaimable Images:"
dangling_count=$(docker images --filter "dangling=true" -q | wc -l | tr -d ' ')
if [ $dangling_count -gt 0 ]; then
    echo "      Dangling Images:"
    docker image ls --filter "dangling=true" --format "      🔸 {{.Repository}}:{{.Tag}} ({{.ID}}) - {{.Size}}" 2>/dev/null
fi

# Prüfe auf Images ohne Container (nur mit docker system df -v möglich)
echo "      Hinweis: $img_reclaim sind aufräumbar (dangling + ungenutzte Layer)"
if [ "$img_reclaim" != "0B" ] && [ $dangling_count -eq 0 ]; then
    echo "      ℹ️  Keine dangling Images, aber ungenutzte Image-Layer vorhanden"
elif [ $dangling_count -eq 0 ]; then
    echo "      ✅ Keine reclaimable Images"
fi
echo ""

echo "2. Container (writable layers):"
container_count=$(docker ps -a -q | wc -l | tr -d ' ')
container_line=$(echo "$SYS_DF" | grep "Containers")
container_size=$(echo "$container_line" | awk '{print $4}')
container_reclaim=$(echo "$container_line" | awk '{print $5}')
echo "   Anzahl: $container_count Container"
echo "   Größe: $container_size (davon $container_reclaim aufräumbar)"

# Liste stopped/exited Container auf
echo "   Reclaimable Container (exited):"
docker ps -a --filter "status=exited" --format "      🔸 {{.Names}} ({{.ID}}) - {{.Status}}" 2>/dev/null | head -10
if [ $(docker ps -a --filter "status=exited" -q | wc -l | tr -d ' ') -eq 0 ]; then
    echo "      ✅ Keine gestoppten Container"
fi
echo ""

echo "3. Volumes:"
vol_count=$(docker volume ls -q | wc -l | tr -d ' ')
vol_line=$(echo "$SYS_DF" | grep "Local Volumes")
vol_size=$(echo "$vol_line" | awk '{print $5}')
vol_reclaim=$(echo "$vol_line" | awk '{print $6}')
echo "   Anzahl: $vol_count Volumes"
echo "   Größe: $vol_size (davon $vol_reclaim aufräumbar)"

# Liste ungenutzte Volumes auf
echo "   Reclaimable Volumes (nicht an Container gebunden):"
dangling_vol_count=$(docker volume ls --filter "dangling=true" -q | wc -l | tr -d ' ')
if [ $dangling_vol_count -gt 0 ]; then
    docker volume ls --filter "dangling=true" --format "      🔸 {{.Name}}" 2>/dev/null
    echo "      ℹ️  Gesamt: $dangling_vol_count Volumes"
else
    echo "      ✅ Keine ungenutzten Volumes"
fi
echo ""

echo "4. Build Cache:"
cache_line=$(echo "$SYS_DF" | grep "Build Cache")
cache_size=$(echo "$cache_line" | awk '{print $4}')
cache_reclaim=$(echo "$cache_line" | awk '{print $5}')
echo "   Größe: $cache_size (davon $cache_reclaim aufräumbar)"
echo ""

echo "----------------------------------------"
echo "GESAMT (docker system df):"
docker system df
echo ""
echo "ℹ️  HINWEIS zur Interpretation:"
echo "   - 'RECLAIMABLE' zeigt theoretisch löschbare Daten"
echo "   - Images: Meist ungenutzte Images (mit -a flag löschbar)"
echo "   - Volumes: 0B = alle Volumes werden von Containern verwendet"
echo ""

echo "Aufräum-Befehle (NICHT automatisch ausgeführt):"
echo "  docker system prune              # Ungenutzte Container, Networks, dangling Images"
echo "  docker system prune -a           # + alle ungenutzten Images"
echo "  docker system prune -a --volumes # + alle ungenutzten Volumes (VORSICHT!)"
echo "  docker image prune -a            # Nur ungenutzte Images"
echo "  docker volume prune              # Nur ungenutzte Volumes"
echo "  docker builder prune             # Nur Build Cache"
echo "  docker builder prune -a          # Gesamter Build Cache"
echo ""
echo "Detaillierte Ansicht:"
echo "  docker system df -v              # Alle Details zu Images, Containern, Volumes"
