# Backup-Tool

Dieses Verzeichnis enthaelt den Bash-basierten Einstiegspunkt und die Modulstruktur fuer backupctl.
Das Tool verwaltet ERPNext/Frappe-Backups ueber mehrere Systeme (lokal, SSH, Docker) ohne zentrale Datenbank.

## Was bedeutet was?

- node_type: Fachliche Art der Backup-Quelle.
	- frappe-node: Frappe/Bench-typische Backup-Struktur (DB, Files, site_config).
	- plain-dir: Allgemeines Verzeichnis mit Backup-Dateien ohne Bench-spezifische Struktur.
- access: Technischer Zugriffsweg auf den Knoten.
	- local: Direkte Ausfuehrung auf dem lokalen Host.
	- docker: Ausfuehrung lokal im Container.
	- ssh: Ausfuehrung auf Remote-Host via SSH.
	- ssh-docker: Ausfuehrung via SSH im Remote-Container.
- Cache: Lokaler, regenerierbarer Index fuer schnelle Suche und Filterung. Liegt unter `~/.cache/backupctl/nodes/<node-id>.json` (eine JSON-Array-Datei pro Knoten). Der Cache ist nie die Wahrheit.
- backup_id: Eindeutige technische Kennung eines logischen Backups. Format: `<node>_<site>_<timestamp>`.
- backup_hash: Kurzform der backup_id (6 Zeichen SHA256). Wird in der Scan-Ausgabe als `[abc123]` angezeigt.
- display_name: Nutzerfreundliche Anzeige. Fallback-Reihenfolge: display_name -> reason -> backup_id.
- source_rel_dir: Relativer Pfad des Backup-Verzeichnisses unterhalb von backup_root (relevant fuer plain-dir mit Unterverzeichnissen).

## Verzeichnisstruktur

- bin/backupctl: CLI-Einstiegspunkt und Command-Dispatcher.
- config/nodes.json: Beispielkonfiguration der bekannten Knoten.
- config/nodes.mkt.json: Reale Konfiguration fuer mkt-Knoten.
- config/nodes.test.json: Testkonfiguration fuer automatisierte Tests.
- lib/common.sh: Gemeinsame Hilfsfunktionen (Fehler, Temp-Verzeichnisse, Cleanup-Trap).
- lib/log.sh: Logging-Helfer (bt_log_info, bt_log_warn, bt_log_error mit ISO-8601-Zeitstempel).
- lib/config.sh: Konfiguration laden und validieren (inkl. vollstaendiger Schema-Validierung).
- lib/nodes.sh: Knotenmodell, Runner, SSH/Docker-Ausfuehrung, Transfer-Helfer, nodes list.
- lib/backup-model.sh: Backup-Datenmodell, Manifest-Schema, backup_id/backup_hash-Generierung.
- lib/scan.sh: Discovery fuer frappe-node und plain-dir (lokal und remote, Single-Pass).
- lib/cache.sh: Cache-Management (per-Node JSON-Arrays, rebuild, clear, upsert, aggregierte Abfrage).
- lib/backup.sh: Backup-Erzeugung (create, nur fuer frappe-node).
- lib/copy.sh: Transferlogik (rsync als Standard, Validierung, Cache-Update).
- lib/restore.sh: Restore, site_config-Modi, Post-Restore-Aufgaben.
- lib/list.sh: Listen- und Filterausgabe (Text/JSON).
- tests/test_backupctl.sh: Zentrales Testscript (27 Tests).

## Abhaengigkeiten

Pflicht:

- bash
- jq
- ssh
- rsync

Optional:

- scp (Fallback fuer Transfers)
- docker (fuer docker und ssh-docker)

## Konfiguration nodes.json erklaert

Finales Format: JSON.

- Standardpfad: ~/.erpnext-nodes.json
- Wenn die Datei noch nicht existiert, wird sie beim ersten Laden aus config/nodes.json initialisiert.
- Root-Feld: nodes (Array)
- Override moeglich via CLI: backupctl --config <path> ...
- Override moeglich via Environment: BACKUPCTL_CONFIG_PATH=<path>

Pflichtfelder je Node:

- id: Eindeutiger Knotenname.
- node_type: Fachliche Quellart.
- access: Technischer Zugriffstyp.
- backup_paths: Liste von Verzeichnissen/Patterns fuer Backup-Suche.

Zusaetzliche Pflicht je nach Typ:

- bei node_type=frappe-node:
	- bench_path: Pfad zum Bench-Kontext.
- bei access=ssh oder ssh-docker:
	- ssh_config: Name des SSH-Config-Eintrags, der fuer `ssh` und `rsync` verwendet wird.

Optionale Felder:

- tags: Knotenkennzeichnungen (z. B. prod, test, customer-a).
- vpn_required: Hinweis fuer Netzwerkzugang.
- description: Freitextbeschreibung.
- enabled: Knoten aktiv/inaktiv.
- ssh_config: SSH-Config-Hostalias fuer Remote-Zugriff.
- container: Containername fuer docker exec.
- compose_service: Service fuer docker compose exec.
- docker_context: Erwarteter lokaler Docker-Context (Default: default) fuer docker.

## CLI-Kommandos und Bedeutung

Hilfe aufrufen:

- backupctl --help
- backupctl help <command>
- backupctl <command> --help

- backupctl nodes list
	- Zeigt konfigurierte Knoten mit node_type/access.
- backupctl --config config/nodes.test.json nodes list
	- Nutzt explizit eine alternative Konfiguration (z. B. fuer Tests).
- backupctl --dry-run <command> ...
	- Fuehrt Kommandos im Planungsmodus aus (keine echten Aenderungen, nur geplante Aktionen).
- backupctl scan [--node <id>]
	- Liest Backups von einem einzelnen Knoten oder, ohne `--node`, von allen konfigurierten Knoten (Single-Pass remote).
	- Ausgabe: `FOUND [<hash>] node=X site=Y kind=Z complete=true|false id=<backup_id>`
- backupctl cache clear
	- Loescht alle lokalen Cache-Dateien unter `~/.cache/backupctl/nodes/`.
- backupctl list [--format text|json] [--node <id>] [--site <site>] [--tag <tag>]
               [--reason-contains <text>] [--complete true|false]
               [--from <iso8601>] [--to <iso8601>]
	- Listet Cache-Eintraege mit optionalen Filtern.
- backupctl create --node <id> --site <site> --reason <text> [--tag <tag>] [--backup-type <type>]
	- Erzeugt auf frappe-node ein neues Backup inkl. Manifest (nur frappe-node).
- backupctl copy --backup <id> --from <source-node> --to <target-node> [--no-validate]
	- Uebertraegt ein Backup zwischen Knoten (rsync, mit optionaler Validierung).
- backupctl restore --backup <id> --to <target-node> --site <target-site>
               [--config-mode use-source-config|merge-config|keep-target-config]
               [--dry-run] [--force] [--no-checks]
	- Stellt ein Backup auf dem Ziel wieder her.

## Restore: site_config Modi

- use-source-config: Quell-datei uebernehmen.
- merge-config (Default): Quelle uebernehmen, aber sensible/zielspezifische Felder schuetzen.
- keep-target-config: Ziel-datei beibehalten.

Aktuell geschuetzte Felder beim Merge:

- db_name
- db_password
- admin_password
- encryption_key
- file_watcher_port

## Post-Restore-Aufgaben (automatisch)

Nach einem `restore` fuehrt das Tool automatisch folgende Schritte aus:

1. `bench migrate --site <site>` - Datenbankmigrationen.
2. `bench fix-permissions --user frappe` - Dateirechte korrigieren.
3. `bench --site <site> clear-cache` - Cache leeren.
4. HTTP-Erreichbarkeit pruefen (`curl localhost:8000/app/home`).

## Typischer Ablauf

1. Konfiguration validieren und Knoten pruefen.
2. `scan` ausfuehren.
3. `list` fuer Auswahl eines Backups nutzen.
4. Optional `create` fuer neues Backup auf frappe-bench.
5. `copy` auf Zielknoten (rsync).
6. `restore` auf Zielsite.
7. Post-Restore-Aufgaben laufen automatisch; Ergebnis-Log pruefen.

## Bekannte Grenzen (Stand MVP)

- `create`: Keine Erzeugung von `apps.json` und `checksums.sha256`.
- `restore`: Kein automatischer Neustart von Containern/Diensten nach Restore.
- `restore`: Keine explizite Produktiv-Schutzflag (--force ist reserviert).
- `copy`/`restore`: Pfadrekonstruktion fuer `source_rel_dir` bei verschachtelten plain-dir Backups noch nicht vollstaendig implementiert.
- Keine Migration von altem globalen `cache.jsonl` auf neue per-Node-Struktur.

## Schnelltest

```bash
cd Units/backup-tool
bash tests/test_backupctl.sh
```
