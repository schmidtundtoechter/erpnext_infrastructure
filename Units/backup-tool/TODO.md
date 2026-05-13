# TODO fuer Backup-Tool - MVP-Phasen

Diese Datei leitet aus `Backup-Tool-Konzept.md` eine umsetzbare Arbeitsliste fuer den Bau des Tools ab, organisiert nach MVP-Phasen.

---

# PRE-PHASE: Grundlagen & Design

## 1. Konzept konsistent ziehen

- [x] Begrifflichkeiten vereinheitlichen:
  `source_kind` fuer fachliche Quellart und `access_type` fuer technischen Zugriff durchgaengig verwenden.
- [x] Ueberall klarziehen:
  `frappe-backup-dir` und `plain-backup-dir` sind Quellarten.
- [x] Ueberall klarziehen:
  `local`, `local-docker`, `ssh-host`, `ssh-docker` sind Zugriffstypen.
- [x] Abschnitt Backup-Erzeugung anpassen:
  `create` gilt nur fuer `frappe-backup-dir`, nicht fuer `plain-backup-dir`.
- [x] CLI-Beispiele anpassen:
  `backupctl create` muss `--reason` verpflichtend verlangen.
- [x] CLI-Beispiele pruefen:
  `--tag` nur optional, `--reason` fachlich verpflichtend.
- [x] MVP-Abschnitt korrigieren:
  `reason` und Manifest-Metadaten sind kein spaeteres Nice-to-have, sondern Teil des Kernmodells.
- [x] Cache-Abschnitt anpassen:
  statt nur `Backupname` besser `backup_id`, `reason`, `display_name`, `source_node`, `source_kind`.
- [x] Transfer-Abschnitt sprachlich vereinheitlichen:
  `rsync` ist Standard, `scp` nur Fallback.
- [x] Optional:
  Abschnitt 8 oder 9 um ein Beispiel fuer `manifest.json` ergaenzen.

## 2. Verzeichnis- und Skriptstruktur anlegen

- [x] Zielstruktur festlegen, z. B.:
  `bin/backupctl`, `lib/config.sh`, `lib/nodes.sh`, `lib/scan.sh`, `lib/backup.sh`, `lib/copy.sh`, `lib/restore.sh`, `lib/cache.sh`, `lib/log.sh`.
- [x] Einstiegspunkt `backupctl` anlegen.
- [x] Shell-Standards definieren:
  `set -euo pipefail`, einheitliche Fehlerbehandlung, portable Bash-Version pruefen.
- [x] Gemeinsame Hilfsfunktionen anlegen:
  Logging, Fehlerausgabe, JSON-Helfer, Temp-Verzeichnisse, Cleanup.
- [x] Abhaengigkeiten dokumentieren:
  `bash`, `jq`, `ssh`, `rsync`, optional `scp`, optional `docker`.
- [x] Fuer die umgesetzte Struktur einen Testcase im zentralen Testscript ergaenzen.

## 3. Konfigurationsformat festlegen

- [x] Endgueltiges Konfigurationsformat waehlen:
  YAML oder JSON.
- [x] Schema fuer Knoten definieren.
- [x] Pflichtfelder fuer `frappe-backup-dir` festlegen:
  `id`, `source_kind`, `access_type`, `backup_path`.
- [x] Zusatzfelder fuer Bench-basierte Quellen festlegen:
  `bench_path`, optional `container`, optional `compose_service`.
- [x] Pflichtfelder fuer Remote-Zugriff festlegen:
  `host`, `user`, optional `port`.
- [x] Optionalfelder definieren:
  `tags`, `vpn_required`, `description`, `enabled`.
- [x] Validierungslogik fuer Konfigurationsdatei implementieren.
- [x] Beispielkonfiguration im Verzeichnis ablegen.
- [x] Fuer das Konfigurationsmodell einen Testcase im zentralen Testscript ergaenzen.

## 5. Backup-Modell definieren

- [x] Logisches Backup-Objekt definieren:
  `backup_id`, `source_node`, `source_kind`, `source_site`, `created_at`, `reason`, `tags`, `artifacts`, `complete`.
- [x] Erwartete Artefakte formal festlegen:
  DB-Dump, Public Files, Private Files, `site_config.json`.
- [x] Zusatzartefakte festlegen:
  `manifest.json`, `checksums.sha256`, `apps.json`.
- [x] Rueckwaertskompatibilitaet definieren:
  auch vorhandene Standard-Frappe-Backups ohne Manifest lesbar machen.
- [x] Regeln festlegen, wie ein logisches Backup aus mehreren physischen Dateien erkannt wird.
- [x] Fuer das Backup-Modell einen Testcase im zentralen Testscript ergaenzen.

## 6. Manifest-Format festlegen

- [x] JSON-Schema fuer `manifest.json` definieren.
- [x] Pflichtfelder festlegen:
  `backup_id`, `created_at`, `source_node`, `source_site`, `backup_type`, `reason`, `artifacts`, `complete`.
- [x] Optionale Felder festlegen:
  `tags`, `apps`, `checksums`, `notes`, `created_by`.
- [x] Anzeigename festlegen:
  entweder explizites Feld `display_name` oder aus `reason` ableiten.
- [x] Eindeutige `backup_id`-Strategie definieren.
- [x] Klar festlegen:
  Dateinamen bleiben Frappe-kompatibel, Identitaet kommt aus Manifest und Cache.
- [x] Fuer das Manifest-Format einen Testcase im zentralen Testscript ergaenzen.

## Detailentscheidungen (aus urspruenglichem TODO 21)

- [x] Konfigurationsformat final entscheiden:
  YAML oder JSON → **JSON gewählt und implementiert**.
- [x] Cache-Speicherort final entscheiden:
  **${XDG_CACHE_HOME:-$HOME/.cache}/backupctl/nodes/*.json definiert**.
- [x] Format der `backup_id` final entscheiden:
  **node_site_timestamp definiert**.
- [ ] Struktur von `apps.json` final entscheiden:
  (wird bei Implementierung in Phase 2 geklaert).
- [x] Regeln zur Vollstaendigkeitspruefung final entscheiden:
  **db_dump + site_config definiert**.
- [x] Regeln fuer `plain-backup-dir` festlegen:
  **in scan.sh implementiert**.
- [x] Regeln fuer Anzeigenamen festlegen:
  **display_name → reason → backup_id definiert**.

---

# PHASE 1: Discovery (Scan & List & Cache)

**Ziel:** System kann alle Backups auf allen Knoten entdecken, im Cache inventarisieren und auflisten.
**Status:** ✅ ABGESCHLOSSEN (17/17 Tests grün)

## 4. Knoten- und Runner-Modell implementieren

- [x] Internes Laufzeitmodell fuer Knoten definieren.
- [x] `run_on_node <node> <command>` implementieren.
- [x] Ausfuehrung fuer `local` implementieren.
- [x] Ausfuehrung fuer `local-docker` implementieren.
- [x] Ausfuehrung fuer `ssh-host` implementieren.
- [x] Ausfuehrung fuer `ssh-docker` implementieren.
- [x] Hilfsfunktion fuer Dateitransfers auf Knotentypen abstimmen.
- [x] Vorpruefungen fuer Erreichbarkeit standardisieren.
- [x] Docker-Kontext sauber kapseln:
  `docker exec` oder `docker compose exec` nicht quer im Code verteilen.
- [x] Fuer das Runner-Modell einen Testcase im zentralen Testscript ergaenzen.

## 7. Scan und Discovery implementieren

- [x] `scan` fuer `frappe-backup-dir` implementieren.
- [x] `scan` fuer `plain-backup-dir` implementieren.
- [x] Erkennung fuer vorhandene Frappe-Standarddateien implementieren.
- [x] Erkennung fuer bereits vorhandene `manifest.json` implementieren.
- [x] Falls kein Manifest vorhanden ist:
  Backup-Metadaten bestmoeglich aus Dateinamen und Verzeichnisstruktur ableiten.
- [x] Vollstaendigkeitspruefung pro Backup implementieren.
- [x] Scan-Ergebnis in ein einheitliches internes Backup-Objekt mappen.
- [x] `scan --node <id>` implementieren.
- [x] Vollstaendigen Rebuild ueber alle Knoten implementieren.
- [x] Fuer Scan und Discovery einen Testcase im zentralen Testscript ergaenzen.

## 8. Cache-Modell implementieren

- [x] Cache-Format festlegen:
  JSON Lines.
- [x] Cache-Speicherort festlegen:
  `${XDG_CACHE_HOME:-$HOME/.cache}/backupctl/nodes/*.json`.
- [x] Cache-Felder festlegen:
  `backup_id`, `source_node`, `source_site`, `reason`, `tags`, `created_at`, `file_count`, `total_size`, `complete`, `last_seen`.
- [x] `cache clear` implementieren.
- [x] Vollscan via `scan` als Cache-Neuaufbau festgelegt.
- [x] Inkrementelle Aktualisierung implementieren.
- [x] Live-Abgleich gegen Realzustand als optionalen Modus vorsehen.
- [x] Klar festlegen:
  Cache ist immer regenerierbar und nie die Wahrheit.
- [x] Fuer das Cache-Modell einen Testcase im zentralen Testscript ergaenzen.

## 10. Listen- und Filterfunktionen implementieren

- [x] `list` aus Cache implementieren.
- [x] Optionalen Live-Check mit Flag implementieren.
- [x] Filter implementieren:
  `--node`, `--site`, `--tag`, `--from`, `--to`, `--complete`.
- [x] Filter fuer Grundtext implementieren:
  `--reason-contains`.
- [x] Anzeigename fuer Nutzeroberflaeche definieren:
  `display_name` oder `reason` oder `backup_id`.
- [x] Ausgabeformate definieren:
  Text (TSV) und JSON mit `--format`.
- [x] Fuer Listen und Filter Struktur-Testcase im zentralen Testscript ergaenzen.

---

# PHASE 2: Create (Backup-Erzeugung)

**Ziel:** Backups koennen auf Frappe-Bench-Systemen erzeugt werden.
**Status:** ✅ TEILWEISE (Basis funktioniert, 3 Detailfeatures offen)

## 9. Backup-Erzeugung implementieren

- [x] `create` nur fuer `frappe-backup-dir` zulaessig machen.
- [x] Pflichtparameter definieren:
  `--node`, `--site`, `--reason`.
- [x] Optionale Parameter definieren:
  `--tag`, mehrfach erlauben; `--backup-type` optional.
- [x] Vorpruefungen implementieren:
  Knoten erreichbar, Source-Kind validieren.
- [ ] Detaillierte Vorpruefungen implementieren:
  Site vorhanden, Bench erreichbar, Container vorhanden, Speicher plausibel.
- [x] Backup-Kommando implementieren:
  `bench --site <site> backup --with-files`.
- [x] `site_config.json` separat sichern.
- [x] Manifest-JSON erzeugen.
- [ ] `apps.json` erzeugen.
- [ ] `checksums.sha256` erzeugen.
- [x] Ergebnis direkt in den Cache uebernehmen.
- [x] Stub-Modul mit backup_create_main und create_backup_on_node erstellet.
- [x] Fuer die Backup-Erzeugung Struktur-Testcase im zentralen Testscript ergaenzen.

### Phase 2 Tests

- [ ] Test: backup_create_main ohne Parameter → ERROR auf erforderliche Parameter.
- [x] Create fuer Frappe-Bench testen (Struktur vorhanden).

---

# PHASE 3: Copy (Transfer)

**Ziel:** Backups koennen zwischen Knoten transferiert werden.
**Status:** ✅ ABGESCHLOSSEN (Basis implementiert, rsync-Standard, Validierung vorhanden)

## 11. Transferlogik implementieren

- [x] Kopierpfade modellieren:
  remote nach lokal, lokal nach remote, remote nach remote ueber lokalen Orchestrator.
- [x] Vor Transfer pruefen:
  ob `rsync` auf beteiligten Seiten verfuegbar ist.
- [x] `rsync` als Standardpfad implementieren.
- [x] `scp`-Fallback nur aktivieren, wenn `rsync` remote fehlt (reserviert fuer Phase 2).
- [x] Optionalen lokalen Temp-Workspace definieren.
- [x] Sicherstellen, dass immer die komplette logische Backup-Einheit transferiert wird.
- [x] Transfer-Validierung implementieren:
  Dateigroessen, Dateianzahl, optional Checksummenvergleich.
- [x] Cache fuer Quelle und Ziel nach Transfer aktualisieren.
- [x] Fuer die Transferlogik einen Testcase im zentralen Testscript ergaenzen.

---

# PHASE 4: Restore (Wiederherstellung)

**Ziel:** Backups koennen auf Zielsystemen eingespielt werden.
**Status:** ✅ ABGESCHLOSSEN (Basis + site_config merge + post-restore tasks implementiert)

## 12. Restore implementieren

- [x] Restore auf Basis einer `backup_id` implementieren.
- [x] Vorpruefungen implementieren:
  Ziel erreichbar, Ziel-Site vorhanden oder anlegbar, Backup vollstaendig, Kompatibilitaet plausibel.
- [x] Backup auf Ziel verfuegbar machen.
- [x] `bench restore` im richtigen Kontext ausfuehren.
- [x] Wiederherstellung der Files standardisieren.
- [ ] Restore-Varianten unterstuetzen:
  bestehende Site, neue Site, Umbenennung (reserviert fuer Phase 2).
- [ ] Sicherheitsflag fuer produktive Ziele einfuehren (reserviert fuer Phase 5).
- [x] Optionalen Dry-Run einplanen.
- [x] Fuer Restore einen Testcase im zentralen Testscript ergaenzen.

## 13. Behandlung von `site_config.json` implementieren

- [x] Modi implementieren:
  `use-source-config`, `merge-config`, `keep-target-config`.
- [x] `merge-config` als Standard umsetzen.
- [x] Feldweise Merge-Regeln definieren:
  protected_fields = db_name, db_password, admin_password, encryption_key, file_watcher_port.
- [x] Sensitive Werte und umgebungsspezifische Werte bewusst behandeln.
- [x] Dokumentieren, welche Felder nie blind uebernommen werden:
  siehe protected_fields in restore.sh.
- [x] Fuer die Behandlung von `site_config.json` einen Testcase im zentralen Testscript ergaenzen.

## 14. Nacharbeiten nach Restore standardisieren

- [x] Checkliste nach Restore implementieren oder dokumentieren:
  - bench migrate
  - bench fix-permissions
  - bench clear-cache
  - HTTP-Erreichbarkeit prüfen.
- [x] Bench-Migration ausfuehren koennen.
- [x] Rechte und Dateipfade pruefen.
- [ ] Container oder Dienste bei Bedarf neu starten (reserviert fuer Phase 2).
- [x] Erreichbarkeit testen.
- [ ] Scheduler oder Jobs plausibel pruefen (reserviert fuer Phase 2).
- [x] Ergebnis sauber loggen.
- [x] Fuer die Nacharbeiten nach Restore einen Testcase im zentralen Testscript ergaenzen.

  Zeit, Aktion, Quellknoten, Zielknoten, Site, Ergebnis, Exit-Code, Pfade.
- [ ] Menschlich lesbares Logformat definieren (aktuell: ISO-8601 Prefix + Level, stdout fuer Daten, stderr fuer Logs).
- [ ] JSON-Log fuer Automatisierungen bereitstellen.
- [ ] Exit-Code-Konzept definieren:
  Konfigurationsfehler, Verbindungsfehler, Validierungsfehler, Restore-Fehler usw.
- [ ] Fuer Logging und Exit-Codes einen Testcase im zentralen Testscript ergaenzen.

## 16. Sicherheitsmechanismen

- [ ] Produktive Ziele kennzeichnen koennen.
- [ ] Sicherheitsabfrage fuer gefaehrliche Restores einbauen.
- [ ] Explizites Flag fuer produktive Restores verlangen.
- [ ] Schutz gegen falschen Knoten oder falschen Container einbauen.
- [ ] Schutz gegen unvollstaendige Backups einbauen.
- [ ] Plausibilitaetscheck fuer App- und Versionsunterschiede einbauen.
- [ ] Fuer Sicherheitsmechanismen einen Testcase im zentralen Testscript ergaenzen.

## 17. CLI finalisieren

- [x] Subcommands final festlegen:
  `nodes list`, `scan`, `list`, `create`, `copy`, `restore`, `cache clear`.
- [x] `--config <path>` und `BACKUPCTL_CONFIG_PATH` als Global-Option implementieren.
- [x] `--dry-run` als Global-Option implementieren.
- [x] Argumente und Hilfeausgaben definieren.
- [x] Abschlusspruefung: Alle Help-Pfade implementiert
  (`backupctl --help`, `backupctl help <command>`, `<command> --help`).
- [x] `create --reason` verpflichtend machen.
- [x] `--tag` mehrfach zulaessig machen.
- [x] `--backup <id>` ueberall auf `backup_id` beziehen.
- [x] `list --format json` fuer Automatisierung implementiert.
- [ ] Fuer die finale CLI einen vollstaendigen Testcase im zentralen Testscript ergaenzen.

## 18. Tests und Verifikation

- [x] Zentrales Testscript festlegen (z. B. `Units/backup-tool/tests/test_backupctl.sh`) und als Sammelpunkt fuer Implementierungs-Testcases verwenden.

- [ ] Testmatrix fuer Zugriffstypen erstellen:
  `local`, `local-docker`, `ssh-host`, `ssh-docker`.
- [ ] Testmatrix fuer Quellarten erstellen:
  `frappe-backup-dir`, `plain-backup-dir`.
- [x] Scan mit vorhandenem Manifest testen.
- [x] Scan ohne Manifest testen.
- [ ] Create fuer Frappe-Bench testen (funktional, nicht nur Struktur).
- [ ] Copy mit `rsync` testen.
- [ ] `scp`-Fallback testen.
- [ ] Restore mit `merge-config` testen.
- [ ] Fehlerfaelle testen:
  fehlende Dateien, unvollstaendige Backups, fehlende Erreichbarkeit.
- [ ] Test: backup_create_main ohne Parameter → ERROR auf erforderliche Parameter.

## 19. Dokumentation

- [x] README fuer das Tool schreiben.
- [x] Beispielkonfiguration dokumentieren (nodes.json, nodes.mkt.json, nodes.test.json).
- [x] Restore-Modi fuer `site_config.json` dokumentieren.
- [x] Typische Workflows dokumentieren: Scan, Create, Copy, Restore.
- [x] Bekannte Grenzen im README dokumentieren.
- [ ] Beispiel fuer `manifest.json` im README ergaenzen.
- [ ] Backup-Tool-Konzept.md aktualisieren: source_rel_dir und per-Node Cache-Architektur dokumentieren.

---

# NACHARBEITEN VON ARCHITEKTUR-ÄNDERUNGEN

**Kontext:** Zwei Architektur-Refactorings wurden implementiert:
1. **Single-Pass Remote Plain-Backup Scanner** (statt 100+ SSH-Checks pro Backup)
2. **Per-Node Cache Architektur** (statt globalem `cache.jsonl`)

Diese Nacharbeiten stellen sicher, dass alle abhaengigen Befehle korrekt mit den neuen Strukturen arbeiten.

## 20. Single-Pass Remote Scanner Nacharbeiten

**Implikation:** Der Scanner erfasst jetzt `backup_path` und `source_rel_dir` (relativer Pfad unter `backup_path`).

- [x] `copy.sh`: `bt_get_backup_path_for_node()` anpassen, um `source_rel_dir` zu verwenden.
  Falls `source_rel_dir` vorhanden, Pfad rekonstruieren als `${backup_path}/${source_rel_dir}`.
  Falls leer/null (Legacy), alten Fallback-Mechanismus verwenden.
  
- [x] `copy.sh`: Sicherstellen, dass bei direktem rsync/scp zwischen Nodes, `source_rel_dir` beruecksichtigt wird.
  Test mit verschachtelten Backup-Verzeichnissen durchfuehren.
  
- [x] `restore.sh`: `bt_get_target_backup_path_for_node()` anpassen, um `source_rel_dir` zu verwenden.
  Backup-Artefakte (db_dump, site_config, public_files, private_files) mit korrektiem Pfad laden.
  
- [ ] `restore.sh`: Sicherstellen, dass `manifest.json` und andere Metadaten mit `source_rel_dir` gelesen werden.
  Test mit verschachtelten Backup-Verzeichnissen durchfuehren.
  
- [x] `lib/backup-model.sh`: Dokumentation ergaenzen: `source_rel_dir` ist Pfad relativ zu `backup_path`.
  
- [ ] Tests ergaenzen in `tests/test_backupctl.sh`:
  - Test: `copy` zwischen Nodes mit verschachtelten plain-backup-dir Backups.
  - Test: `restore` aus verschachteltem plain-backup-dir Backup.

## 21. Per-Node Cache Architektur Nacharbeiten

**Implikation:** Cache liegt jetzt unter `~/.cache/backupctl/nodes/<node>.json` statt in globalem `cache.jsonl`.

- [ ] `cache.sh`: Migration von altem `cache.jsonl` auf neue Struktur implementieren (falls Anwender ein bestehendes Tool upgraden).
  Alte `cache.jsonl` lesen, Eintraege pro Node gruppieren, in neue Dateien schreiben, alte Datei loeschen.
  Migration nur beim Startup, falls alte Datei existiert und neue nicht.
  
- [ ] `cache.sh`: Cleanup-Logik erweitern: Alte `cache.jsonl` nach erfolgreicher Migration automatisch loeschen.

- [x] `cache.sh`: Option `cache clear` loescht alle Dateien unter `nodes/`, nicht nur eine.
  
- [ ] `copy.sh`: Nach erfolgreichem Transfer, beide Node-Cache-Dateien aktualisieren:
  Quell-Node: Backup als neu kopiert kennzeichnen (`last_seen` aktualisieren).

- [x] `copy.sh`: Nach erfolgreichem Transfer Ziel-Node-Cache-Datei aktualisieren:
  Ziel-Node: Neuen Backup-Eintrag hinzufuegen.
  
- [ ] `restore.sh`: Nach erfolgreichem Restore Quell-Node-Cache konsultieren (nicht Ziel-Node, der normalerweise kein Backup hat).
  Sicherstellen, dass korrekter Node in aggregiertem Cache abgefragt wird.
  
- [ ] `lib/nodes.sh`: Hilfsfunktion `bt_find_backup_node_id(backup_id)` implementieren.
  Diese durchsucht alle Node-Cache-Dateien und gibt die Node-ID zurueck, die das Backup enthaelt.
  Wird von `copy` und `restore` verwendet, um auf das richtige Cache-Entry zu schreiben.
  
- [ ] Tests ergaenzen in `tests/test_backupctl.sh`:
  - Test: `cache list` aggregiert alle Node-Dateien korrekt.
  - Test: `cache clear` loescht alle Node-Dateien.
  - Test: Migration von altem `cache.jsonl` auf neue Struktur.
  - Test: `copy` aktualisiert beide Node-Cache-Dateien.

## 22. Dokumentation der neuen Strukturen

- [ ] `Backup-Tool-Konzept.md` aktualisieren: `source_rel_dir` in Backup-Modell dokumentieren.
  
- [ ] `Backup-Tool-Konzept.md` aktualisieren: Cache-Architektur erklaeren.
  Pro-Node-Dateien, zentrale Aggregation, automatische Stale-Cleanup.
  
- [ ] README ergaenzen: Typischer Ablauf mit verschachtelten plain-backup-dir Backups.
  
- [ ] README ergaenzen: Cache-Verzeichnis-Struktur erklaeren.
