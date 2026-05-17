#!/usr/bin/env bash

backup_restore_usage() {
  cat <<'EOF'
Usage: backupctl backup restore --backup <id> --to <node> --site <site> [options]

Options:
  --backup <ref>                             Backup reference: backup_id or backup_hash (required)
  --to <node>                                Target node id (required)
  --site <site>                              Target site (required)
  --config-mode use-source-config|merge-config|keep-target-config
                                             site_config handling mode (default: merge-config)
  --dry-run                                  Simulate restore without changes
  -f, --force                                Skip overwrite confirmation
  --no-checks                                Skip pre-check validations
  -h, --help                                 Show this help
EOF
}

backup_restore_main() {
  local backup_ref="" backup_id="" target_node="" target_site="" config_mode="merge-config" \
    dry_run="" force="" no_checks=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        backup_restore_usage
        return
        ;;
      --backup)
        backup_ref="$2"
        shift 2
        ;;
      --to)
        target_node="$2"
        shift 2
        ;;
      --site)
        target_site="$2"
        shift 2
        ;;
      --config-mode)
        config_mode="$2"
        shift 2
        ;;
      --dry-run)
        dry_run="1"
        shift
        ;;
      -f|--force)
        force="1"
        shift
        ;;
      --no-checks)
        no_checks="1"
        shift
        ;;
      *)
        bt_die "Unknown restore option: $1"
        ;;
    esac
  done
  
  [[ -n "${backup_ref}" ]] || bt_die "restore: --backup is required"
  [[ -n "${target_node}" ]] || bt_die "restore: --to is required"
  [[ -n "${target_site}" ]] || bt_die "restore: --site is required"
  
  # Validiere config_mode
  case "${config_mode}" in
    use-source-config|merge-config|keep-target-config)
      ;;
    *)
      bt_die "restore: invalid config-mode: ${config_mode}"
      ;;
  esac
  
  bt_require_loaded_config

  backup_id="$(bt_resolve_backup_ref_to_id "${backup_ref}")"
  
  restore_backup_to_node "${backup_id}" "${target_node}" "${target_site}" \
    "${config_mode}" "${dry_run}" "${force}" "${no_checks}"
}

restore_backup_to_node() {
  local backup_id="$1"
  local target_node="$2"
  local target_site="$3"
  local config_mode="$4"
  local dry_run="${5:-}"
  local force="${6:-}"
  local no_checks="${7:-}"
  
  bt_log_info "Restoring backup: backup_id=${backup_id} to=${target_node} site=${target_site} config_mode=${config_mode}"
  
  if [[ -n "${dry_run}" || "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "DRY-RUN: Would restore ${backup_id} to ${target_node}/${target_site}"
    return
  fi

  # Hole Backup vom Cache (egal auf welchem Knoten es ist)
  local backup_path bench_path backup_entry source_node target_backup_entry
  backup_entry="$(bt_cache_list_all | jq -c --arg bid "${backup_id}" 'map(select(.backup_id == $bid))[0] // empty')"
  [[ -n "${backup_entry}" && "${backup_entry}" != "null" ]] || bt_die "Backup ${backup_id} not found in cache"
  
  source_node="$(jq -r '.source_node // empty' <<<"${backup_entry}")"
  [[ -n "${source_node}" ]] || bt_die "Backup ${backup_id} has no source_node metadata"

  bench_path="$(bt_node_bench_path "${target_node}")"

  # Vorpruefungen inkl. App-Kompatibilitaet VOR Confirm-Prompt
  if [[ -z "${no_checks}" ]]; then
    bt_check_node_reachability "${target_node}" || bt_die "Target node ${target_node} is not reachable"
    bt_restore_check_app_compatibility "${backup_entry}" "${target_node}" "${target_site}" "${bench_path}"
  fi

  bt_confirm_or_force "${force}" "Restore will overwrite data for site ${target_site} on node ${target_node}. Continue?"

  if [[ -z "${no_checks}" ]]; then
    local site_check
    site_check="curl -s http://localhost:8000/api/resource/Website >/dev/null 2>&1"
    run_on_node "${target_node}" "${site_check}" >/dev/null 2>&1 || \
      bt_log_warn "Could not verify target site exists (may be new site)"
  fi
  
  # ============================================================================
  # Restore-Ablauf: Quelle pruefen -> Ziel pruefen/kopieren -> einspielen
  # Cache ist initiale Quelle, Node-Dateisystem ist maßgeblich.
  # ============================================================================
  local source_backup_path source_artifacts source_db_dump_name source_db_dump
  local source_public_name source_private_name source_site_config_name source_rel_dir
  local target_backup_path db_dump public_files private_files config_file

  source_artifacts="$(jq -c '.artifacts // {}' <<<"${backup_entry}")"
  source_db_dump_name="$(jq -r '.db_dump // empty' <<<"${source_artifacts}")"
  source_public_name="$(jq -r '.public_files // empty' <<<"${source_artifacts}")"
  source_private_name="$(jq -r '.private_files // empty' <<<"${source_artifacts}")"
  source_site_config_name="$(jq -r '.site_config // empty' <<<"${source_artifacts}")"
  source_rel_dir="$(jq -r '.source_rel_dir // empty' <<<"${backup_entry}")"

  [[ -n "${source_db_dump_name}" ]] || \
    bt_die "Restore: no db_dump artifact found for backup ${backup_id}"

  # 1) Quelle pruefen: liegt das Backup dort wirklich?
  source_backup_path="$(bt_get_backup_path_for_node "${source_node}" "${backup_id}" "${backup_entry}")" || \
    bt_die "Restore: could not determine source backup path for node ${source_node}"
  source_db_dump="${source_backup_path%/}/${source_db_dump_name}"
  if ! run_on_node "${source_node}" "[[ -f $(bt_quote "${source_db_dump}") ]]" >/dev/null 2>&1; then
    bt_die "Restore: source backup not found on node ${source_node}: ${source_db_dump}"
  fi

  # 2) Ziel pruefen, falls noetig kopieren
  target_backup_path="$(bt_get_target_backup_path_for_node "${target_node}" "${backup_id}" "${backup_entry}")" || \
    bt_die "Restore: could not determine target backup path for node ${target_node}"
  db_dump="${target_backup_path%/}/${source_db_dump_name}"

  if ! run_on_node "${target_node}" "[[ -f $(bt_quote "${db_dump}") ]]" >/dev/null 2>&1; then
    if [[ "${source_node}" == "${target_node}" ]]; then
      bt_die "Restore: backup expected on target/source node ${target_node} but not found at ${db_dump}"
    fi

    bt_log_info "Backup not present on target node; copying from ${source_node} to ${target_node}..."
    copy_backup_between_nodes "${backup_id}" "${source_node}" "${target_node}" "${force}" "1" "${backup_entry}" || \
      bt_die "Failed to copy backup to target node"

    # Nach Copy muss Datei am erwarteten Ort liegen; sonst harter Fehler.
    if ! run_on_node "${target_node}" "[[ -f $(bt_quote "${db_dump}") ]]" >/dev/null 2>&1; then
      bt_die "Restore: backup was copied but db_dump is not at expected target path: ${db_dump}"
    fi

    # Cache nach erfolgreicher Verfuegbarkeit auf Ziel aktualisieren.
    bt_cache_upsert_entry "$(bt_get_cached_backup_object "${target_node}" "${backup_id}" "${backup_entry}")"
  fi

  # 3) Einspielen vom Zielpfad
  bt_log_info "Restore preparation verified: backup available on target at ${db_dump}"

  public_files="${target_backup_path%/}/${source_public_name}"
  private_files="${target_backup_path%/}/${source_private_name}"
  config_file="${target_backup_path%/}/${source_site_config_name}"
  
  # Handle site_config.json gemäß config_mode (nur wenn Datei vorhanden ist)
  if [[ -n "${source_site_config_name}" && -n "${config_file}" && "${config_file}" != "${target_backup_path}/" ]]; then
    if [[ "${config_mode}" != "use-source-config" ]]; then
      bt_handle_site_config_merge "${backup_id}" "${target_node}" "${target_site}" \
        "${config_file}" "${config_mode}" "${bench_path}"
    fi
  fi
  
  # DB-Root-Zugang fuer bench restore ermitteln:
  # 1) Node-Config (db_root_user/db_root_password)
  # 2) common_site_config.json (root_login/root_password)
  # 3) MariaDB-Container-Env via docker inspect (fuer ssh-docker Knoten)
  # 4) Interaktive Passwortabfrage als Fallback
  local db_root_password db_root_user node_json_for_pw common_site_config_path common_cfg_raw
  node_json_for_pw="$(bt_get_node_json "${target_node}")"
  db_root_user="$(jq -r '.db_root_user // empty' <<<"${node_json_for_pw}")"
  db_root_password="$(jq -r '.db_root_password // empty' <<<"${node_json_for_pw}")"

  if [[ -z "${db_root_password}" ]]; then
    common_site_config_path="${bench_path}/sites/common_site_config.json"
    common_cfg_raw="$(run_on_node "${target_node}" "cat $(bt_quote "${common_site_config_path}")" 2>/dev/null || true)"

    if [[ -n "${common_cfg_raw}" ]] && jq -e . >/dev/null 2>&1 <<<"${common_cfg_raw}"; then
      if [[ -z "${db_root_user}" ]]; then
        db_root_user="$(jq -r '.root_login // .db_root_user // empty' <<<"${common_cfg_raw}")"
      fi
      db_root_password="$(jq -r '.root_password // .db_root_password // .mariadb_root_password // empty' <<<"${common_cfg_raw}")"
      [[ -n "${db_root_password}" ]] && bt_log_info "Using db_root_password from common_site_config.json"
    else
      bt_log_warn "Could not read common_site_config.json from node '${target_node}' (SSH/container issue or file missing)"
    fi
  fi

  # Fallback fuer ssh-docker: MariaDB-Root-Passwort direkt aus Container-Env lesen.
  # Die DB-Container-Env enthaelt typischerweise MYSQL_ROOT_PASSWORD / MARIADB_ROOT_PASSWORD.
  # DB-Container-Name wird aus dem Frontend-Container-Namen abgeleitet (_frontend_ -> _db_).
  if [[ -z "${db_root_password}" ]]; then
    local _node_access _frontend_container
    _node_access="$(jq -r '.access // empty' <<<"${node_json_for_pw}")"
    _frontend_container="$(jq -r '.container // empty' <<<"${node_json_for_pw}")"
    if [[ "${_node_access}" == "ssh-docker" && "${_frontend_container}" == *"_frontend_container" ]]; then
      local _db_container _ssh_base _env_pw _inspect_cmd
      _db_container="${_frontend_container/_frontend_container/_db_container}"
      _ssh_base="$(bt_build_ssh_base_cmd "${node_json_for_pw}")"
      _inspect_cmd="${_ssh_base} \"docker inspect ${_db_container} --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD)=' | head -1 | cut -d= -f2-\""
      _env_pw="$(eval "${_inspect_cmd}" 2>/dev/null || true)"
      if [[ -n "${_env_pw}" ]]; then
        db_root_password="${_env_pw}"
        bt_log_info "Using db_root_password from MariaDB container '${_db_container}' environment"
      else
        bt_log_warn "Could not read db_root_password from MariaDB container '${_db_container}'"
      fi
    fi
  fi

  [[ -n "${db_root_user}" ]] || db_root_user="root"

  if [[ -z "${db_root_password}" ]]; then
    bt_log_info "No db_root_password configured for node '${target_node}'."
    printf 'Enter MariaDB/MySQL root password for bench restore: ' >&2
    read -rs db_root_password </dev/tty
    printf '\n' >&2
  fi

  # Führe bench restore aus
  local bench_cmd
  if [[ -n "${db_root_password}" ]]; then
    bench_cmd="cd $(bt_quote "${bench_path}") && bench --site $(bt_quote "${target_site}") restore $(bt_quote "${db_dump}") --db-root-username $(bt_quote "${db_root_user}") --db-root-password $(bt_quote "${db_root_password}")"
  else
    bench_cmd="cd $(bt_quote "${bench_path}") && bench --site $(bt_quote "${target_site}") restore $(bt_quote "${db_dump}")"
  fi

  bt_log_info "Executing bench restore for site ${target_site}..."
  local restore_output
  if ! restore_output="$(run_on_node "${target_node}" "${bench_cmd}" 2>&1)"; then
    printf '%s\n' "${restore_output}" >&2
    if grep -Eiq "Access denied for user '.*'@'" <<<"${restore_output}"; then
      bt_die "Bench restore failed due to DB host permissions. User '${db_root_user}' may not be allowed from app-container host/IP. Check mysql.user grants for '${db_root_user}' (host='%') or configure a dedicated db_root_user/db_root_password for this node."
    fi
    bt_die "Bench restore failed"
  fi
  printf '%s\n' "${restore_output}"
  
  # Restore Files wenn vorhanden
  if run_on_node "${target_node}" "[[ -f ${public_files} ]]" >/dev/null 2>&1; then
    bt_restore_files_to_site "${target_node}" "${target_site}" "${public_files}" "public" "${bench_path}"
  fi
  
  if run_on_node "${target_node}" "[[ -f ${private_files} ]]" >/dev/null 2>&1; then
    bt_restore_files_to_site "${target_node}" "${target_site}" "${private_files}" "private" "${bench_path}"
  fi
  
  # Post-Restore Aufgaben
  bt_execute_post_restore_tasks "${backup_id}" "${target_node}" "${target_site}" "${bench_path}"
  
  bt_log_info "Restore completed: ${backup_id} restored to ${target_site} on ${target_node}"
}

bt_restore_check_app_compatibility() {
  local backup_entry="$1"
  local target_node="$2"
  local target_site="$3"
  local bench_path="$4"
  local backup_apps_json target_apps_json compat_report

  backup_apps_json="$(jq -c '.apps // []' <<<"${backup_entry}")"
  if ! jq -e 'type == "array" and length > 0' <<<"${backup_apps_json}" >/dev/null 2>&1; then
    bt_die "Restore compatibility check failed: backup manifest has no app metadata. Create/scan a backup with apps list or use --no-checks."
  fi

  target_apps_json="$(bt_collect_site_apps_json "${target_node}" "${target_site}" "${bench_path}")"
  if ! jq -e 'type == "array" and length > 0' <<<"${target_apps_json}" >/dev/null 2>&1; then
    bt_die "Restore compatibility check failed: could not determine target app installation (no apps.txt and no apps in bench/apps). Use --no-checks to bypass."
  fi

  compat_report="$(jq -cn \
    --argjson backup_apps "${backup_apps_json}" \
    --argjson target_apps "${target_apps_json}" '
      def normalize($arr):
        ($arr // [])
        | map({
            app: (.app // ""),
            version: (.version // ""),
            branch: (.branch // "")
          })
        | map(select(.app != ""));

      (normalize($backup_apps)) as $b
      | (normalize($target_apps)) as $t
      | {
          missing_apps: [ $b[] | select((.app as $a | ($t | map(.app) | index($a))) == null) | .app ],
          version_mismatches: [
            $b[] as $src
            | $t[]
            | select(.app == $src.app)
            | select(($src.version != "") and (.version != "") and (.version != $src.version))
            | {app: .app, backup_version: $src.version, target_version: .version}
          ],
          branch_mismatches: [
            $b[] as $src
            | $t[]
            | select(.app == $src.app)
            | select(($src.branch != "") and (.branch != "") and (.branch != $src.branch))
            | {app: .app, backup_branch: $src.branch, target_branch: .branch}
          ]
        }
    ')"

  if jq -e '(.missing_apps | length) > 0 or (.version_mismatches | length) > 0 or (.branch_mismatches | length) > 0' <<<"${compat_report}" >/dev/null 2>&1; then
    bt_die "Restore compatibility check failed before overwrite prompt:
$(jq -r '
  [
    (if (.missing_apps|length)>0 then "missing apps on target: " + (.missing_apps|join(", ")) else empty end),
    (if (.version_mismatches|length)>0 then "version mismatches: " + (.version_mismatches|map(.app + " (backup=" + .backup_version + ", target=" + .target_version + ")")|join("; ")) else empty end),
    (if (.branch_mismatches|length)>0 then "branch mismatches: " + (.branch_mismatches|map(.app + " (backup=" + .backup_branch + ", target=" + .target_branch + ")")|join("; ")) else empty end)
  ] | join("\n")
' <<<"${compat_report}")"
  fi

  bt_log_info "App compatibility check passed for ${target_site} on ${target_node}"
}

bt_handle_site_config_merge() {
  local backup_id="$1"
  local target_node="$2"
  local target_site="$3"
  local source_config_file="$4"
  local config_mode="$5"
  local bench_path="$6"
  
  bt_log_info "Handling site_config.json with mode: ${config_mode}"
  
  local target_config_path site_path
  site_path="${bench_path}/sites/${target_site}"
  target_config_path="${site_path}/site_config.json"
  
  case "${config_mode}" in
    use-source-config)
      # Übernehme Quellconfig komplett
      bt_log_info "Copying source site_config.json"
      run_on_node "${target_node}" "cp $(bt_quote "${source_config_file}") $(bt_quote "${target_config_path}")" || \
        bt_log_warn "Failed to copy source site_config.json"
      ;;
      
    keep-target-config)
      # Behalte Zielconfig komplett – nichts tun
      bt_log_info "Keeping target site_config.json"
      return
      ;;
      
    merge-config)
      # Merge: Behalte protected Fields vom Ziel, übernehme andere von Quelle
      bt_log_info "Merging site_config.json..."
      
      # Configs lokal einlesen, mit jq mergen, Ergebnis zurückschreiben
      local source_cfg target_cfg merged_cfg
      source_cfg="$(run_on_node "${target_node}" "cat $(bt_quote "${source_config_file}")" 2>/dev/null || echo '{}')"
      target_cfg="$(run_on_node "${target_node}" "cat $(bt_quote "${target_config_path}")" 2>/dev/null || echo '{}')"

      [[ -n "${source_cfg}" ]] || source_cfg='{}'
      [[ -n "${target_cfg}" ]] || target_cfg='{}'
      jq -e . >/dev/null 2>&1 <<<"${source_cfg}" || source_cfg='{}'
      jq -e . >/dev/null 2>&1 <<<"${target_cfg}" || target_cfg='{}'
      
      # Merge lokal: Starte mit source, überschreibe protected fields mit target-Werten
      merged_cfg="$(jq -s '.[0] as $source | .[1] as $target | $source | .db_name = ($target.db_name // .db_name) | .db_password = ($target.db_password // .db_password) | .admin_password = ($target.admin_password // .admin_password) | .encryption_key = ($target.encryption_key // .encryption_key) | .file_watcher_port = ($target.file_watcher_port // .file_watcher_port)' \
        <(printf '%s' "${source_cfg}") <(printf '%s' "${target_cfg}") 2>/dev/null || echo '')"
      
      if [[ -n "${merged_cfg}" ]] && echo "${merged_cfg}" | jq -e . >/dev/null 2>&1; then
        # Merged JSON auf Ziel-Node schreiben (ohne stdin-Weitergabe, um leere Dateien zu vermeiden)
        if run_on_node "${target_node}" "printf '%s' $(bt_quote "${merged_cfg}") > $(bt_quote "${target_config_path}")" \
          && run_on_node "${target_node}" "python3 -c \"import json,sys; json.load(open(sys.argv[1], 'r', encoding='utf-8'))\" $(bt_quote "${target_config_path}")" >/dev/null 2>&1; then
          bt_log_info "Site config merge completed"
        else
          bt_log_warn "Could not write valid merged site_config.json"
        fi
      else
        bt_log_warn "Merge produced invalid JSON – keeping target site_config.json unchanged"
      fi
      ;;
  esac
}


bt_restore_files_to_site() {
  local node_id="$1"
  local site="$2"
  local tar_file="$3"
  local file_type="$4"  # "public" oder "private"
  local bench_path="$5"
  
  local extract_cmd site_path
  site_path="${bench_path}/sites/${site}"
  
  if [[ "${file_type}" == "public" ]]; then
    extract_cmd="cd $(bt_quote "${site_path}") && tar -xf $(bt_quote "${tar_file}") -C public/"
  else
    extract_cmd="cd $(bt_quote "${site_path}") && tar -xf $(bt_quote "${tar_file}") -C private/"
  fi
  
  bt_log_info "Extracting ${file_type} files for site ${site}..."
  if run_on_node "${node_id}" "${extract_cmd}"; then
    bt_normalize_restored_files_layout "${node_id}" "${site_path}" "${file_type}"
  else
    bt_log_warn "File extraction for ${file_type} may have failed"
  fi
}

bt_normalize_restored_files_layout() {
  local node_id="$1"
  local site_path="$2"
  local file_type="$3"

  # Some backups include site-prefixed paths like public/<old-site>/public/files.
  # Move these into <site>/<public|private>/files to keep Frappe's expected layout.
  local normalize_cmd
  normalize_cmd="site_path=$(bt_quote "${site_path}"); file_type=$(bt_quote "${file_type}"); target_dir=\"\${site_path}/\${file_type}/files\"; mkdir -p \"\${target_dir}\"; moved=0; for nested in \"\${site_path}/\${file_type}\"/*/\"\${file_type}\"/files; do [[ -d \"\${nested}\" ]] || continue; moved=1; find \"\${nested}\" -mindepth 1 -maxdepth 1 -exec mv -n {} \"\${target_dir}/\" \\; ; done; if [[ \"\${moved}\" -eq 1 ]]; then find \"\${site_path}/\${file_type}\" -mindepth 1 -maxdepth 3 -type d -empty -delete; fi"

  if run_on_node "${node_id}" "${normalize_cmd}"; then
    bt_log_info "Normalized restored ${file_type} files layout for site path ${site_path}"
  else
    bt_log_warn "Could not normalize restored ${file_type} files layout for site path ${site_path}"
  fi
}

bt_execute_post_restore_tasks() {
  local backup_id="$1"
  local target_node="$2"
  local target_site="$3"
  local bench_path="$4"
  
  bt_log_info "Executing post-restore tasks..."
  
  # 1. Bench-Migration wenn nötig
  local migration_cmd
  migration_cmd="cd $(bt_quote "${bench_path}") && bench --site ${target_site} migrate"
  run_on_node "${target_node}" "${migration_cmd}" || bt_log_warn "Bench migration failed (site may need manual attention)"
  
  # 3. Clear Cache
  local clear_cache_cmd
  clear_cache_cmd="cd $(bt_quote "${bench_path}") && bench --site ${target_site} clear-cache"
  run_on_node "${target_node}" "${clear_cache_cmd}" || bt_log_warn "Clear cache failed"
  
  # 4. Erreichbarkeit testen (bench-based)
  local site_status_cmd
  site_status_cmd="cd $(bt_quote "${bench_path}") && bench --site ${target_site} list-apps"
  if run_on_node "${target_node}" "${site_status_cmd}" >/dev/null 2>&1; then
    bt_log_info "Post-restore verification passed: site is operational"
  else
    bt_log_warn "Post-restore verification warning: bench list-apps failed for site ${target_site}"
  fi
  
  bt_log_info "Post-restore tasks completed"
}
