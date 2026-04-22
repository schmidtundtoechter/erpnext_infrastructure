# TODO fuer Backup-Tool

Diese Datei leitet aus `Backup-Tool-Konzept.md` eine umsetzbare Arbeitsliste fuer den Bau des Tools ab.

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
  `id`, `source_kind`, `access_type`, `backup_paths`.
- [x] Zusatzfelder fuer Bench-basierte Quellen festlegen:
  `bench_path`, optional `container`, optional `compose_service`.
- [x] Pflichtfelder fuer Remote-Zugriff festlegen:
  `host`, `user`, optional `port`.
- [x] Optionalfelder definieren:
  `tags`, `vpn_required`, `description`, `enabled`.
- [x] Validierungslogik fuer Konfigurationsdatei implementieren.
- [x] Beispielkonfiguration im Verzeichnis ablegen.
- [x] Fuer das Konfigurationsmodell einen Testcase im zentralen Testscript ergaenzen.

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

- [ ] Cache-Format festlegen:
  JSON oder JSON Lines.
- [ ] Cache-Speicherort festlegen.
- [ ] Cache-Felder festlegen:
  `backup_id`, `source_node`, `source_kind`, `site`, `reason`, `tags`, `created_at`, `files`, `size`, `complete`, `last_seen`.
- [ ] `cache clear` implementieren.
- [ ] `cache rebuild` implementieren.
- [ ] Inkrementelle Aktualisierung implementieren.
- [ ] Live-Abgleich gegen Realzustand als optionalen Modus vorsehen.
- [ ] Klar festlegen:
  Cache ist immer regenerierbar und nie die Wahrheit.
- [ ] Fuer das Cache-Modell einen Testcase im zentralen Testscript ergaenzen.

## 9. Backup-Erzeugung implementieren

- [ ] `create` nur fuer `frappe-backup-dir` zulaessig machen.
- [ ] Pflichtparameter definieren:
  `--node`, `--site`, `--reason`.
- [ ] Optionale Parameter definieren:
  `--tag`, mehrfach erlauben; optional `--backup-type`.
- [ ] Vorpruefungen implementieren:
  Knoten erreichbar, Site vorhanden, Bench erreichbar, Container vorhanden, Speicher plausibel.
- [ ] Backup-Kommando implementieren:
  `bench --site <site> backup --with-files`.
- [ ] `site_config.json` separat sichern.
- [ ] `apps.json` erzeugen oder aus installierten Apps ableiten.
- [ ] `checksums.sha256` erzeugen.
- [ ] `manifest.json` erzeugen.
- [ ] Ergebnis direkt in den Cache uebernehmen oder Folgescan ausfuehren.
- [ ] Fuer die Backup-Erzeugung einen Testcase im zentralen Testscript ergaenzen.

## 10. Listen- und Filterfunktionen implementieren

- [ ] `list` aus Cache implementieren.
- [ ] Optionalen Live-Check implementieren.
- [ ] Filter implementieren:
  `--node`, `--site`, `--tag`, `--from`, `--to`, `--complete`.
- [ ] Filter fuer Grundtext implementieren:
  z. B. `--reason-contains`.
- [ ] Anzeigename fuer Nutzeroberflaeche definieren:
  `reason` oder abgeleitete lesbare Kurzfassung.
- [ ] Ausgabeformate definieren:
  menschenlesbar und JSON.
- [ ] Fuer Listen und Filter einen Testcase im zentralen Testscript ergaenzen.

## 11. Transferlogik implementieren

- [ ] Kopierpfade modellieren:
  remote nach lokal, lokal nach remote, remote nach remote ueber lokalen Orchestrator.
- [ ] Vor Transfer pruefen:
  ob `rsync` auf beteiligten Seiten verfuegbar ist.
- [ ] `rsync` als Standardpfad implementieren.
- [ ] `scp`-Fallback nur aktivieren, wenn `rsync` remote fehlt.
- [ ] Optionalen lokalen Temp-Workspace definieren.
- [ ] Sicherstellen, dass immer die komplette logische Backup-Einheit transferiert wird.
- [ ] Transfer-Validierung implementieren:
  Dateigroessen, Dateianzahl, optional Checksummenvergleich.
- [ ] Cache fuer Quelle und Ziel nach Transfer aktualisieren.
- [ ] Fuer die Transferlogik einen Testcase im zentralen Testscript ergaenzen.

## 12. Restore implementieren

- [ ] Restore auf Basis einer `backup_id` implementieren.
- [ ] Vorpruefungen implementieren:
  Ziel erreichbar, Ziel-Site vorhanden oder anlegbar, Backup vollstaendig, Kompatibilitaet plausibel.
- [ ] Backup auf Ziel verfuegbar machen.
- [ ] `bench restore` im richtigen Kontext ausfuehren.
- [ ] Wiederherstellung der Files standardisieren.
- [ ] Restore-Varianten unterstuetzen:
  bestehende Site, neue Site, Umbenennung.
- [ ] Sicherheitsflag fuer produktive Ziele einfuehren.
- [ ] Optionalen Dry-Run einplanen.
- [ ] Fuer Restore einen Testcase im zentralen Testscript ergaenzen.

## 13. Behandlung von `site_config.json` implementieren

- [ ] Modi implementieren:
  `use-source-config`, `merge-config`, `keep-target-config`.
- [ ] `merge-config` als Standard umsetzen.
- [ ] Feldweise Merge-Regeln definieren.
- [ ] Sensitive Werte und umgebungsspezifische Werte bewusst behandeln.
- [ ] Dokumentieren, welche Felder nie blind uebernommen werden.
- [ ] Fuer die Behandlung von `site_config.json` einen Testcase im zentralen Testscript ergaenzen.

## 14. Nacharbeiten nach Restore standardisieren

- [ ] Checkliste nach Restore implementieren oder dokumentieren.
- [ ] Bench-Migration ausfuehren koennen.
- [ ] Rechte und Dateipfade pruefen.
- [ ] Container oder Dienste bei Bedarf neu starten.
- [ ] Erreichbarkeit testen.
- [ ] Scheduler oder Jobs plausibel pruefen.
- [ ] Ergebnis sauber loggen.
- [ ] Fuer die Nacharbeiten nach Restore einen Testcase im zentralen Testscript ergaenzen.

## 15. Logging und Exit-Codes

- [ ] Einheitliches Logging implementieren.
- [ ] Pflichtfelder im Log sicherstellen:
  Zeit, Aktion, Quellknoten, Zielknoten, Site, Ergebnis, Exit-Code, Pfade.
- [ ] Menschlich lesbares Logformat definieren.
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

- [ ] Subcommands final festlegen:
  `nodes list`, `scan`, `list`, `create`, `copy`, `restore`, `cache clear`, `cache rebuild`.
- [ ] Argumente und Hilfeausgaben definieren.
- [ ] `create --reason` verpflichtend machen.
- [ ] `--tag` mehrfach zulaessig machen.
- [ ] `--backup <id>` ueberall auf `backup_id` beziehen.
- [ ] JSON-Ausgabeoptionen fuer Automatisierung einbauen.
- [ ] Fuer die finale CLI einen Testcase im zentralen Testscript ergaenzen.

## 18. Tests und Verifikation

- [ ] Zentrales Testscript festlegen (z. B. `Units/backup-tool/tests/test_backupctl.sh`) und als Sammelpunkt fuer Implementierungs-Testcases verwenden.

- [ ] Testmatrix fuer Zugriffstypen erstellen:
  `local`, `local-docker`, `ssh-host`, `ssh-docker`.
- [ ] Testmatrix fuer Quellarten erstellen:
  `frappe-backup-dir`, `plain-backup-dir`.
- [ ] Scan mit vorhandenem Manifest testen.
- [ ] Scan ohne Manifest testen.
- [ ] Create fuer Frappe-Bench testen.
- [ ] Copy mit `rsync` testen.
- [ ] `scp`-Fallback testen.
- [ ] Restore mit `merge-config` testen.
- [ ] Fehlerfaelle testen:
  fehlende Dateien, unvollstaendige Backups, fehlende Erreichbarkeit.

## 19. Dokumentation

- [ ] README fuer das Tool schreiben.
- [ ] Beispielkonfiguration dokumentieren.
- [ ] Beispiel fuer `manifest.json` dokumentieren.
- [ ] Restore-Modi fuer `site_config.json` dokumentieren.
- [ ] Typische Workflows dokumentieren:
  Scan, Create, Copy, Restore.
- [ ] Grenzen des MVP dokumentieren.

## 20. MVP-Reihenfolge

- [ ] Phase 1:
  Konfiguration laden, Knotenmodell, Runner, Scan, Cache, `list`.
- [ ] Phase 2:
  `create` fuer `frappe-backup-dir` mit verpflichtendem `--reason` und Manifest.
- [ ] Phase 3:
  `copy` mit `rsync` als Standard und `scp`-Fallback.
- [ ] Phase 4:
  `restore` mit `merge-config` als Standard.
- [ ] Phase 5:
  Logging verfeinern, Sicherheitsflags, Live-Checks, Dry-Run.

## 21. Offene Detailentscheidungen

- [ ] Konfigurationsformat final entscheiden:
  YAML oder JSON.
- [ ] Cache-Speicherort final entscheiden.
- [ ] Format der `backup_id` final entscheiden.
- [ ] Struktur von `apps.json` final entscheiden.
- [ ] Regeln zur Vollstaendigkeitspruefung final entscheiden.
- [ ] Regeln fuer `plain-backup-dir` festlegen:
  welche Dateimuster als zusammengehoeriges Backup gelten.
- [ ] Regeln fuer Anzeigenamen festlegen:
  nur `reason` oder Kombination aus `reason`, `site`, `created_at`.
