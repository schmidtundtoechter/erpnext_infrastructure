# Backup-Tool (MVP Scaffold)

Dieses Verzeichnis enthaelt den Startpunkt und die Modulstruktur fuer `backupctl`.

## Verzeichnisstruktur

- `bin/backupctl` - CLI-Einstiegspunkt
- `lib/common.sh` - gemeinsame Hilfsfunktionen
- `lib/log.sh` - Logging-Helfer
- `lib/config.sh` - Konfiguration laden
- `lib/nodes.sh` - Knotenoperationen
- `lib/scan.sh` - Scan/Discovery
- `lib/backup.sh` - Backup-Erzeugung
- `lib/copy.sh` - Transfer
- `lib/restore.sh` - Restore
- `lib/cache.sh` - Cache-Funktionen
- `tests/test_backupctl.sh` - zentrales Testscript

## Abhaengigkeiten

Pflicht:

- `bash`
- `jq`
- `ssh`
- `rsync`

Optional:

- `scp` (Fallback)
- `docker` (fuer Docker-basierte Zugriffstypen)

## Schnelltest

```bash
cd Units/backup-tool
bash tests/test_backupctl.sh
```