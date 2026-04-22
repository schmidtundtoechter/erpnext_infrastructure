# Backup-Tool (MVP Scaffold)

Dieses Verzeichnis enthaelt den Bash-basierten Einstiegspunkt und die Modulstruktur fuer backupctl.
Das Tool verwaltet ERPNext/Frappe-Backups ueber mehrere Systeme (lokal, SSH, Docker) ohne zentrale Datenbank.

## Was bedeutet was?

- source_kind: Fachliche Art der Backup-Quelle.
	- frappe-backup-dir: Frappe/Bench-typische Backup-Struktur (DB, Files, site_config).
	- plain-backup-dir: Allgemeines Verzeichnis mit Backup-Dateien ohne Bench-spezifische Struktur.
- access_type: Technischer Zugriffsweg auf den Knoten.
	- local: Direkte Ausfuehrung auf dem lokalen Host.
	- local-docker: Ausfuehrung lokal im Container.
	- ssh-host: Ausfuehrung auf Remote-Host via SSH.
	- ssh-docker: Ausfuehrung via SSH im Remote-Container.
- Cache: Lokaler, regenerierbarer Index fuer schnelle Suche und Filterung. Der Cache ist nie die Wahrheit.
- backup_id: Eindeutige technische Kennung eines logischen Backups.
- display_name: Nutzerfreundliche Anzeige. Fallback-Reihenfolge: display_name -> reason -> backup_id.

## Verzeichnisstruktur

- bin/backupctl: CLI-Einstiegspunkt und Command-Dispatcher.
- config/nodes.json: Beispielkonfiguration der bekannten Knoten.
- lib/common.sh: Gemeinsame Hilfsfunktionen (Fehler, Utilities).
- lib/log.sh: Logging-Helfer.
- lib/config.sh: Konfiguration laden und validieren.
- lib/nodes.sh: Knotenmodell, Runner, SSH/Docker-Ausfuehrung, Transfer-Helfer.
- lib/backup-model.sh: Backup-Datenmodell und Manifest-Schema.
- lib/scan.sh: Discovery fuer frappe-backup-dir und plain-backup-dir.
- lib/cache.sh: Cache-Management (JSON Lines, rebuild, clear, incremental update).
- lib/backup.sh: Backup-Erzeugung (create).
- lib/copy.sh: Transferlogik (rsync als Standardpfad, Validierung, Cache-Update).
- lib/restore.sh: Restore, site_config-Modi, Post-Restore-Aufgaben.
- lib/list.sh: Listen- und Filterausgabe (Text/JSON).
- tests/test_backupctl.sh: Zentrales Testscript.

## Abhaengigkeiten

Pflicht:

- bash
- jq
- ssh
- rsync

Optional:

- scp (Fallback fuer Transfers)
- docker (fuer local-docker und ssh-docker)

## Konfiguration nodes.json erklaert

Finales Format: JSON.

- Standardpfad: config/nodes.json
- Root-Feld: nodes (Array)
- Override moeglich via CLI: backupctl --config <path> ...
- Override moeglich via Environment: BACKUPCTL_CONFIG_PATH=<path>

Pflichtfelder je Node:

- id: Eindeutiger Knotenname.
- source_kind: Fachliche Quellart.
- access_type: Technischer Zugriffstyp.
- backup_paths: Liste von Verzeichnissen/Patterns fuer Backup-Suche.

Zusaetzliche Pflicht je nach Typ:

- bei source_kind=frappe-backup-dir:
	- bench_path: Pfad zum Bench-Kontext.
- bei access_type=ssh-host oder ssh-docker:
	- host
	- user
	- port optional (Default 22)

Optionale Felder:

- tags: Knotenkennzeichnungen (z. B. prod, test, customer-a).
- vpn_required: Hinweis fuer Netzwerkzugang.
- description: Freitextbeschreibung.
- enabled: Knoten aktiv/inaktiv.
- container: Containername fuer docker exec.
- compose_service: Service fuer docker compose exec.
- docker_context: Erwarteter lokaler Docker-Context (Default: default) fuer local-docker.

## CLI-Kommandos und Bedeutung

- backupctl nodes list
	- Zeigt konfigurierte Knoten mit source_kind/access_type.
- backupctl --config config/nodes.test.json nodes list
	- Nutzt explizit eine alternative Konfiguration (z. B. fuer Tests).
- backupctl --dry-run <command> ...
	- Fuehrt Kommandos im Planungsmodus aus (keine echten Aenderungen, nur geplante Aktionen).
- backupctl scan --node <id>
	- Liest Backups vom Zielknoten und mappt sie auf das interne Modell.
- backupctl cache rebuild
	- Baut den lokalen Cache vollstaendig aus Realzustand neu auf.
- backupctl list --format text|json [Filter]
	- Listet Cache-Eintraege und filtert z. B. nach node/site/tag/zeitraum/complete.
- backupctl create --node <id> --site <site> --reason <text>
	- Erzeugt auf frappe-backup-dir ein neues Backup inkl. Manifest.
- backupctl copy --backup <id> --from <source-node> --to <target-node>
	- Uebertraegt ein Backup zwischen Knoten.
- backupctl restore --backup <id> --to <target-node> --site <target-site>
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

## Typischer Ablauf

1. Konfiguration validieren und Knoten pruefen.
2. scan oder cache rebuild ausfuehren.
3. list fuer Auswahl eines Backups nutzen.
4. Optional create fuer neues Backup.
5. copy auf Zielknoten.
6. restore auf Zielsite.
7. Post-Restore-Aufgaben und Verifikation prüfen.

## Schnelltest

```bash
cd Units/backup-tool
bash tests/test_backupctl.sh
```
