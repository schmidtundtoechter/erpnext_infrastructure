# Backup-Tool (MVP Scaffold)

Dieses Verzeichnis enthaelt den Startpunkt und die Modulstruktur fuer `backupctl`.

## Verzeichnisstruktur

- `bin/backupctl` - CLI-Einstiegspunkt
- `config/nodes.json` - Beispielkonfiguration
- `lib/common.sh` - gemeinsame Hilfsfunktionen
- `lib/log.sh` - Logging-Helfer
- `lib/config.sh` - Konfiguration laden und validieren
- `lib/nodes.sh` - Knotenmodell, Runner und Transfer-Helfer
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

## Konfigurationsformat

Das finale Format ist JSON.

- Standardpfad: `config/nodes.json`
- Root-Feld: `nodes` (Array)
- Quellarten (`source_kind`): `frappe-backup-dir`, `plain-backup-dir`
- Zugriffstypen (`access_type`): `local`, `local-docker`, `ssh-host`, `ssh-docker`

Pflichtfelder je Node:

- `id`
- `source_kind`
- `access_type`
- `backup_paths`

Zusaetzlich bei `source_kind=frappe-backup-dir`:

- `bench_path`

Zusaetzlich bei `access_type=ssh-host|ssh-docker`:

- `host`
- `user`
- optional `port`

Optionalfelder:

- `tags`
- `vpn_required`
- `description`
- `enabled`
- `container`
- `compose_service`

## Schnelltest

```bash
cd Units/backup-tool
bash tests/test_backupctl.sh
```
