# Backup-Tool – Architektur- und Code-Review

**Datum:** 2026-05-07  
**Reviewer:** Claude (automatisierter Review)  
**Schwerpunkt:** Robustheit, DRY-Prinzip, Konsistenz, Komplexität

---

## Zusammenfassung

Das Tool ist insgesamt gut strukturiert: klare Modultrennung, durchgängige Nutzung von `jq` für JSON, einheitliches Logging. Die Hauptprobleme liegen in drei Bereichen: (1) kritische Robustheitslücken, die zur Laufzeit scheitern können, (2) systematische Code-Duplikation vor allem rund um jq-Hilfsfunktionen, und (3) inkonsistentes Dry-run-Handling.

---

## KRITISCH – Robustheit

### ~~C1 · `restore.sh` ignoriert `artifacts`-Objekt: hardcodierte `latest-*`-Namen~~ ✅ GEFIXT

**Datei:** [`lib/restore.sh`](lib/restore.sh)  
**Gefixt am:** 2026-05-07

Artifact-Namen werden jetzt korrekt aus dem Cache-Eintrag gelesen:
```bash
artifacts_obj="$(jq -r '.artifacts // {}' <<<"${target_backup_entry}")"
db_dump="${backup_path}/$(jq -r '.db_dump // empty' <<<"${artifacts_obj}")"
public_files="${backup_path}/$(jq -r '.public_files // empty' <<<"${artifacts_obj}")"
private_files="${backup_path}/$(jq -r '.private_files // empty' <<<"${artifacts_obj}")"
config_file="${backup_path}/$(jq -r '.site_config // empty' <<<"${artifacts_obj}")"
```

---

### ~~C2 · Pfadvariablen ohne `bt_quote` in Remote-Befehlen~~ ✅ GEFIXT

**Dateien:** [`lib/copy.sh`](lib/copy.sh)  
**Gefixt am:** 2026-05-07

`bt_validate_backup_transfer` in `copy.sh` verwendet jetzt `bt_quote` für `target_path`:
```bash
check_cmd="[[ -d $(bt_quote "${target_path}") ]] && [[ -n \"\$(ls -A $(bt_quote "${target_path}") 2>/dev/null)\" ]]"
```
`bt_restore_files_to_site` in `restore.sh` verwendete bereits durchgängig `bt_quote`.

---

### ~~C3 · `bt_cache_filter` interpoliert User-Input direkt in jq-Code~~ ✅ GEFIXT

**Datei:** [`lib/cache.sh`](lib/cache.sh)  
**Gefixt am:** 2026-05-07

Alle Filter-Parameter werden jetzt sicher über `--arg` an jq übergeben – kein User-Input mehr im jq-Ausdruck selbst:
```bash
jq -c \
  --arg node      "${node_filter}" \
  --arg site      "${site_filter}" \
  --arg tag       "${tag_filter}" \
  --arg reason    "${reason_contains}" \
  --arg complete  "${complete_filter}" \
  --arg from_date "${from_date}" \
  --arg to_date   "${to_date}" \
  '.[] | select($node == "" or .source_node == $node) | ...' <<<"${json_lines}"
```

---

### ~~C4 · `bt_get_cached_backup_object` baut JSON per Heredoc-String-Interpolation~~ ✅ GEFIXT

**Datei:** [`lib/copy.sh`](lib/copy.sh)  
**Gefixt am:** 2026-05-07

Der Fallback-Pfad verwendet jetzt `jq -cn --arg` – kein Heredoc mehr, kein doppelter `bt_get_node_json`-Aufruf:
```bash
jq -cn \
  --arg backup_id   "${backup_id}" \
  --arg backup_hash "${backup_hash}" \
  --arg node_id     "${node_id}" \
  --arg backup_path "${backup_path}" \
  --arg now         "${now}" \
  '{backup_id: $backup_id, backup_hash: $backup_hash, source_node: $node_id,
    backup_path: $backup_path, source_rel_dir: "",
    created_at: $now, last_seen: $now, complete: true}'
```

---

### ~~C5 · `bt_handle_site_config_merge`: Modus `use-source-config` tut nichts~~ ✅ GEFIXT

**Datei:** [`lib/restore.sh`](lib/restore.sh)  
**Gefixt am:** 2026-05-07

Der `use-source-config`-Branch kopiert die Quellconfig jetzt korrekt auf den Zielknoten:
```bash
use-source-config)
  bt_log_info "Copying source site_config.json"
  run_on_node "${target_node}" "cp $(bt_quote "${source_config_file}") $(bt_quote "${target_config_path}")" || \
    bt_log_warn "Failed to copy source site_config.json"
  ;;
```

---

### ~~C6 · `bt_handle_site_config_merge`: `for field in $(jq -r 'keys[]')` bricht bei Feldnamen mit Leerzeichen~~ ✅ GEFIXT

**Datei:** [`lib/restore.sh`](lib/restore.sh)  
**Gefixt am:** 2026-05-07

Merge erfolgt jetzt in einem einzigen `jq -s`-Aufruf ohne Pro-Feld-Subshell:
```bash
merged_cfg="$(jq -s '.[0] as $source | .[1] as $target
  | $source
  | .db_name = ($target.db_name // .db_name)
  | .db_password = ($target.db_password // .db_password)
  | .admin_password = ($target.admin_password // .admin_password)
  | .encryption_key = ($target.encryption_key // .encryption_key)
  | .file_watcher_port = ($target.file_watcher_port // .file_watcher_port)' \
  <(printf '%s' "${source_cfg}") <(printf '%s' "${target_cfg}") 2>/dev/null || echo '')"
```

---

## WICHTIG – DRY-Verletzungen / Duplikation

### D1 · `normalize_node_type` und `normalize_access` in 6+ jq-Aufrufen wiederholt

**Datei:** [`lib/config.sh`](lib/config.sh) (5×), [`lib/nodes.sh:239–256`](lib/nodes.sh) (1×)

Die jq-Funktionen werden in jedem einzelnen `jq`-Aufruf neu definiert:

```jq
def normalize_node_type:
  if . == "frappe-backup-dir" then "frappe-node" ...
```

In `bt_validate_config` allein erscheinen sie 4-mal. `bt_normalize_node_json` tut das noch einmal separat. `nodes_list` ebenfalls.

Die Normalisierung existiert bereits als Shell-Funktion `bt_normalize_node_json`. Die Validierung sollte entweder eine einzige jq-Datei/`--jsonargs`-Kette sein, oder die normalize-Definitionen werden in einen gemeinsamen jq-Include ausgelagert.

**Minimaler Fix:** `bt_validate_config` auf einen einzigen kombinierten `jq`-Aufruf reduzieren, der alle 5 Prüfungen gleichzeitig ausführt.

---

### D2 · `bt_scan_relative_dir` existiert, wird aber an 2+ Stellen inline kopiert

**Funktion:** [`lib/scan.sh:146–158`](lib/scan.sh)  
**Inline-Kopien:** [`lib/scan.sh:290–291`](lib/scan.sh), [`lib/scan.sh:321–322`](lib/scan.sh), [`lib/backup-model.sh:176–178`](lib/backup-model.sh)

```bash
# Drei unterschiedliche Stellen mit identischer Logik:
rel_dir="${backup_dir#"${backup_root%/}/"}"
[[ "${rel_dir}" == "${backup_dir}" ]] && rel_dir=""
```

Die Funktion `bt_scan_relative_dir` sollte überall genutzt werden.

---

### D3 · `bt_backup_display_name` und `bt_list_get_display_name` sind identisch

**Dateien:** [`lib/backup-model.sh:194–197`](lib/backup-model.sh), [`lib/list.sh:172–176`](lib/list.sh)

```bash
jq -r '.display_name // .reason // .backup_id' <<<"${backup_obj_json}"
```

Exakt die gleiche Zeile in zwei verschiedenen Funktionen. Eine davon streichen.

---

### D4 · `run_on_node` ruft `bt_get_node_json` zweimal auf

**Datei:** [`lib/nodes.sh:149–170`](lib/nodes.sh)

```bash
run_on_node() {
  runner_cmd="$(bt_build_run_command "${node_id}" "${command}")"  # bt_get_node_json intern
  # ...
  node_json="$(bt_get_node_json "${node_id}")"  # nochmal
  access="$(jq -r '.access' <<<"${node_json}")"
```

`bt_build_run_command` liest den Node schon komplett. Das Ergebnis sollte weitergereich werden, statt nochmal abzufragen.

---

### D5 · `bt_run_with_timeout` / `bt_eval_with_timeout`: nahezu identischer Python-Inlineblock

**Datei:** [`lib/common.sh:41–89`](lib/common.sh)

Beide Funktionen haben denselben Python-Code mit `subprocess.run` + Timeout + Exit-Code-Forwarding. Der einzige Unterschied: eine übergibt `cmd` direkt, die andere wrappt in `bash -lc`. Der Python-Block könnte eine gemeinsame Hilfsfunktion sein.

---

### D6 · `bt_cache_replace_node_backups` dupliziert `bt_cache_build_entry`-Logik

**Datei:** [`lib/cache.sh:199–208`](lib/cache.sh)

```bash
bt_cache_replace_node_backups() {
  timestamp="$(date -u ...)"
  cache_entries="$(jq --arg last_seen "${timestamp}" '[ .[] + {last_seen: $last_seen} ]' ...)"
```

`bt_cache_build_entry` (Zeile 233) macht genau das – `backup + {last_seen}`. `bt_cache_replace_node_backups` sollte diese Funktion nutzen oder auf den gemeinsamen jq-Ausdruck verweisen.

---

### D7 · `bt_cache_add_entry` ist ein überflüssiger Alias

**Datei:** [`lib/cache.sh:243–247`](lib/cache.sh)

```bash
bt_cache_add_entry() {
  bt_cache_upsert_entry "${backup_obj_json}"
}
```

Fügt keine Funktionalität hinzu. Entweder die Funktion entfernen und direkt `bt_cache_upsert_entry` aufrufen, oder dokumentieren warum sie als separater Einstiegspunkt existiert.

---

## WICHTIG – Inkonsistenz

### ~~I1 · Dry-run: globale `BT_RUNNER_MODE`-Variable UND lokale `--dry-run`-Flag für Restore~~ ✅ GEFIXT

**Datei:** [`bin/backupctl`](bin/backupctl)  
**Gefixt am:** 2026-05-07

Die redundante `--dry-run`-Injektion in `backupctl` wurde entfernt. `BT_RUNNER_MODE` wird vor dem `case`-Statement bereits exportiert – `backup_restore_main` wird nun direkt wie alle anderen Kommandos aufgerufen:
```bash
restore)
  backup_restore_main "$@"
  ;;
```
Nutzer können `--dry-run` weiterhin explizit auf der Kommandozeile übergeben.

---

### ~~I2 · Dry-run-Prüfung fehlt in mehreren kritischen `restore.sh`-Pfaden~~ ✅ GEFIXT

**Datei:** [`lib/restore.sh`](lib/restore.sh)  
**Gefixt am:** 2026-05-07

`restore_backup_to_node` prüft jetzt beide Quellen:
```bash
if [[ -n "${dry_run}" || "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
  bt_log_info "DRY-RUN: Would restore ${backup_id} to ${target_node}/${target_site}"
  return
fi
```

---

### I3 · `nodes_list` in `nodes.sh` statt in `config.sh`

**Datei:** [`lib/nodes.sh:235–257`](lib/nodes.sh)

`nodes_list` listet Knoten aus der Config – es ist keine Node-Runtime-Logik. Die Funktion passt inhaltlich besser nach `config.sh`. Cosmetic, aber erschwert die Orientierung.

---

## MITTLERE PROBLEME – Komplexität / Sauberkeit

### M1 · `scan_main` definiert Funktionen zur Laufzeit (keine echten lokalen Funktionen)

**Datei:** [`lib/scan.sh:573–624`](lib/scan.sh)

```bash
scan_main() {
  bt_scan_print_reports() { ... }
  _scan_and_cache() { ... }
```

In Bash gibt es keine function-scoped Funktionen. Diese Definitionen überschreiben den globalen Namespace und werden bei jedem Aufruf von `scan_main` neu definiert. Beides sollte als Top-Level-Funktion außerhalb von `scan_main` definiert werden.

---

### M2 · `bt_scan_collect_node_backups` und `bt_cache_scan_state_rows_json`: O(n²) JSON-Akkumulation

**Dateien:** [`lib/scan.sh:533–545`](lib/scan.sh), [`lib/cache.sh:82–119`](lib/cache.sh)

```bash
while IFS= read -r backup_json; do
  collected_backups="$(jq --argjson entry "${backup_json}" '. + [$entry]' <<<"${collected_backups}")"
done
```

Jede Iteration startet einen neuen `jq`-Prozess und wächst die Payload. Bei 50 Backups sind das 50 jq-Prozesse, bei 500 wären es 500. Pattern:

```bash
# Besser: alle Zeilen sammeln, einmal verarbeiten
collected_backups="$(scan_node "${node_id}" | jq -s '.')"
```

---

### M3 · `bt_validate_config` lädt die Config-Datei 5-mal von Disk

**Datei:** [`lib/config.sh:55–160`](lib/config.sh)

Fünf separate `jq`-Aufrufe mit `"${config_path}"` als Argument. Alle könnten in einem einzigen Aufruf kombiniert werden, der alle Regeln prüft. Nebenbei würden die duplizierten `normalize`-Definitionen (D1) entfallen.

---

### M4 · `remove_backup_by_id` ist totes Code

**Datei:** [`lib/remove.sh:122–132`](lib/remove.sh)

`remove_backup_by_id` wird intern von nichts aufgerufen. `backup_remove_main` ruft direkt `remove_backup_entry` auf. Die Funktion ist entweder zu streichen oder als offizieller Einstiegspunkt zu dokumentieren.

---

### M5 · `bt_json_get` / `bt_json_set` in `common.sh` sind totes Code

**Datei:** [`lib/common.sh:117–133`](lib/common.sh)

Generische Wrapper-Funktionen, die nirgendwo im Tool aufgerufen werden.

---

### M6 · `bt_scan_update_local_manifest_hash` und `bt_scan_update_remote_manifest_hash`: viel Parallellogik

**Datei:** [`lib/scan.sh:95–144`](lib/scan.sh)

Beide Funktionen prüfen ob `backup_hash` sich geändert hat und schreiben ihn zurück. Die gemeinsame Logik (Hash-Vergleich, Tmp-Datei-Pattern) könnte in eine private Hilfsfunktion mit einem `local/remote`-Parameter extrahiert werden – zumindest der Vergleichsteil.

---

## KLEINERE ANMERKUNGEN

| # | Datei | Beobachtung |
|---|-------|-------------|
| K1 | [`lib/backup.sh:130`](lib/backup.sh) | `tags_list` zu JSON: `printf '[%s]\n' "$(printf '"%s",' ${tags_list}...)"` – bricht bei Tags mit Leerzeichen oder Anführungszeichen. `jq -n --args '$ARGS.positional'` wäre robust. |
| K2 | [`lib/restore.sh:111`](lib/restore.sh) | Site-Check via `curl` auf hardcoded `Administrator:admin` – sollte nicht in produktiver Code sein. |
| K3 | [`lib/restore.sh:278–279`](lib/restore.sh) | Post-Restore URL-Check auf `http://localhost:8000` – nicht anpassbar, falsches Positiv-/Negativ-Verhältnis. |
| K4 | [`lib/copy.sh:1–6`](lib/copy.sh) | TODO-Kommentare am Dateianfang (`# TODO 11`) – sind diese noch aktuell oder erledigt? |
| K5 | [`lib/restore.sh:1–3`](lib/restore.sh) | Dasselbe: `# TODO 12-14` am Dateianfang, obwohl die Funktionen implementiert sind. |
| K6 | [`lib/nodes.sh:193`](lib/nodes.sh) | `bt_check_node_reachability` führt bei ssh/ssh-docker `eval` auf einem `ssh_base true`-String durch – konsistent mit dem Rest, aber sollte eine explizite Array-Form bevorzugen wenn möglich. |

---

## Priorisierte Handlungsempfehlungen

### Sofort (blockieren Korrektheit)
1. ~~**C1** – Restore auf tatsächliche `artifacts`-Felder umstellen~~ ✅ GEFIXT
2. ~~**C5** – `use-source-config` implementieren~~ ✅ GEFIXT
3. ~~**C3** – `bt_cache_filter` auf `--arg`-basierte jq-Abfragen umstellen~~ ✅ GEFIXT
4. ~~**C4** – `bt_get_cached_backup_object` auf `jq -n --arg` umstellen~~ ✅ GEFIXT

### Kurzfristig (Robustheit und Konsistenz)
5. ~~**C2** – Alle Remote-Befehle mit fehlenden `bt_quote`-Aufrufen fixen~~ ✅ GEFIXT
6. ~~**C6** – `bt_handle_site_config_merge` auf einzigen jq-Merge umstellen~~ ✅ GEFIXT
7. ~~**I1** – Dry-run auf einheitliches `BT_RUNNER_MODE`-Pattern konsolidieren~~ ✅ GEFIXT
8. ~~**I2** – `restore_backup_to_node` gegen `BT_RUNNER_MODE` absichern~~ ✅ GEFIXT

### Mittelfristig (DRY / Wartbarkeit)
9. **D1** – `normalize_node_type`/`normalize_access` aus `bt_validate_config` zusammenfassen
10. **D2** – `bt_scan_relative_dir` überall nutzen
11. **D3** – Eine der beiden `display_name`-Funktionen streichen
12. **M1** – Nested Funktionen in `scan_main` nach oben heben
13. **M2** – O(n²) JSON-Loops durch `jq -s` ersetzen
14. **M4/M5** – Tote Funktionen entfernen (`remove_backup_by_id`, `bt_json_get`, `bt_json_set`)
15. **D7** – `bt_cache_add_entry`-Alias entfernen oder begründen
