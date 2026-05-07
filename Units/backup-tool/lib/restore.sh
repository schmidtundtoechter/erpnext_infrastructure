#!/usr/bin/env bash

# TODO 12-14: Restore implementieren mit site_config.json Handling und Nacharbeiten

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
  
  if [[ -n "${dry_run}" ]]; then
    bt_log_info "DRY-RUN: Would restore ${backup_id} to ${target_node}/${target_site}"
    return
  fi

  bt_confirm_or_force "${force}" "Restore will overwrite data for site ${target_site} on node ${target_node}. Continue?"
  
  # Vorpruefungen
  if [[ -z "${no_checks}" ]]; then
    bt_check_node_reachability "${target_node}" || bt_die "Target node ${target_node} is not reachable"
    
    # Prüfe ob Site existiert oder anlegbar ist
    local site_check
    site_check="curl -s http://localhost:8000/api/resource/Website -u Administrator:admin >/dev/null 2>&1"
    run_on_node "${target_node}" "${site_check}" >/dev/null 2>&1 || \
      bt_log_warn "Could not verify target site exists (may be new site)"
  fi
  
  # Hole Backup vom Cache (egal auf welchem Knoten es ist)
  local backup_path bench_path backup_entry source_node target_backup_entry
  backup_entry="$(bt_cache_list_all | jq -c --arg bid "${backup_id}" 'map(select(.backup_id == $bid))[0] // empty')"
  [[ -n "${backup_entry}" && "${backup_entry}" != "null" ]] || bt_die "Backup ${backup_id} not found in cache"
  
  source_node="$(jq -r '.source_node // empty' <<<"${backup_entry}")"
  [[ -n "${source_node}" ]] || bt_die "Backup ${backup_id} has no source_node metadata"
  
  # Prüfe ob Backup bereits auf Zielknoten existiert
  target_backup_entry="$(bt_cache_list_all | jq -c --arg bid "${backup_id}" --arg node "${target_node}" 'map(select(.backup_id == $bid and .source_node == $node))[0] // empty')"
  
  if [[ -z "${target_backup_entry}" || "${target_backup_entry}" == "null" ]]; then
    # Backup muss kopiert werden
    if [[ "${source_node}" != "${target_node}" ]]; then
      bt_log_info "Backup not yet on target node; copying from ${source_node} to ${target_node}..."
      copy_backup_between_nodes "${backup_id}" "${source_node}" "${target_node}" "${force}" "1" "${backup_entry}" || \
        bt_die "Failed to copy backup to target node"
      
      # Neu laden nach Copy
      target_backup_entry="$(bt_cache_list_all | jq -c --arg bid "${backup_id}" --arg node "${target_node}" 'map(select(.backup_id == $bid and .source_node == $node))[0] // empty')"
    else
      target_backup_entry="${backup_entry}"
    fi
  fi
  
  backup_path="$(bt_get_backup_path_for_node "${target_node}" "${backup_id}" "${target_backup_entry}")" || \
    bt_die "Backup ${backup_id} not found on target node"

  bench_path="$(bt_node_bench_path "${target_node}")"
  
  # Extrahiere Dateien aus Backup – verwende die Artifact-Namen aus dem Cache
  local db_dump public_files private_files config_file artifacts_obj
  artifacts_obj="$(jq -r '.artifacts // {}' <<<"${target_backup_entry}")"
  
  db_dump="${backup_path}/$(jq -r '.db_dump // empty' <<<"${artifacts_obj}")"
  public_files="${backup_path}/$(jq -r '.public_files // empty' <<<"${artifacts_obj}")"
  private_files="${backup_path}/$(jq -r '.private_files // empty' <<<"${artifacts_obj}")"
  config_file="${backup_path}/$(jq -r '.site_config // empty' <<<"${artifacts_obj}")"
  
  [[ -n "${db_dump}" && "${db_dump}" != "${backup_path}/" ]] || \
    bt_die "Restore: no db_dump artifact found for backup ${backup_id}"
  
  # Handle site_config.json gemäß config_mode (nur wenn Datei vorhanden ist)
  if [[ -n "${config_file}" && "${config_file}" != "${backup_path}/" ]]; then
    if [[ "${config_mode}" != "use-source-config" ]]; then
      bt_handle_site_config_merge "${backup_id}" "${target_node}" "${target_site}" \
        "${config_file}" "${config_mode}" "${bench_path}"
    fi
  fi
  
  # Führe bench restore aus
  local bench_cmd
  bench_cmd="cd $(bt_quote "${bench_path}") && bench --site ${target_site} restore ${db_dump}"
  
  bt_log_info "Executing bench restore for site ${target_site}..."
  run_on_node "${target_node}" "${bench_cmd}" || bt_die "Bench restore failed"
  
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

# TODO 13: Behandlung von site_config.json
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
      
      # Merge lokal: Starte mit source, überschreibe protected fields mit target-Werten
      merged_cfg="$(jq -s '.[0] as $source | .[1] as $target | $source | .db_name = ($target.db_name // .db_name) | .db_password = ($target.db_password // .db_password) | .admin_password = ($target.admin_password // .admin_password) | .encryption_key = ($target.encryption_key // .encryption_key) | .file_watcher_port = ($target.file_watcher_port // .file_watcher_port)' \
        <(printf '%s' "${source_cfg}") <(printf '%s' "${target_cfg}") 2>/dev/null || echo '')"
      
      if [[ -n "${merged_cfg}" ]] && echo "${merged_cfg}" | jq -e . >/dev/null 2>&1; then
        # Merged JSON auf Ziel-Node schreiben
        run_on_node "${target_node}" "cat > $(bt_quote "${target_config_path}")" <<<"${merged_cfg}" || \
          bt_log_warn "Could not write merged site_config.json"
        bt_log_info "Site config merge completed"
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
    extract_cmd="cd ${site_path} && tar -xf ${tar_file} -C public/"
  else
    extract_cmd="cd ${site_path} && tar -xf ${tar_file} -C private/"
  fi
  
  bt_log_info "Extracting ${file_type} files for site ${site}..."
  run_on_node "${node_id}" "${extract_cmd}" || bt_log_warn "File extraction for ${file_type} may have failed"
}

# TODO 14: Post-Restore Aufgaben
bt_execute_post_restore_tasks() {
  local backup_id="$1"
  local target_node="$2"
  local target_site="$3"
  local bench_path="$4"
  
  bt_log_info "Executing post-restore tasks..."
  
  # 1. Bench-Migration wenn nötig
  local migration_cmd
  migration_cmd="cd $(bt_quote "${bench_path}") && bench migrate --site ${target_site}"
  run_on_node "${target_node}" "${migration_cmd}" || bt_log_warn "Bench migration failed (site may need manual attention)"
  
  # 2. Rechte und Dateipfade prüfen
  local fix_perms_cmd
  fix_perms_cmd="cd $(bt_quote "${bench_path}") && bench fix-permissions --user frappe"
  run_on_node "${target_node}" "${fix_perms_cmd}" || bt_log_warn "Fix permissions failed"
  
  # 3. Clear Cache
  local clear_cache_cmd
  clear_cache_cmd="cd $(bt_quote "${bench_path}") && bench --site ${target_site} clear-cache"
  run_on_node "${target_node}" "${clear_cache_cmd}" || bt_log_warn "Clear cache failed"
  
  # 4. Erreichbarkeit testen (einfacher Check)
  local url_check
  url_check="curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/app/home"
  local http_code
  http_code="$(run_on_node "${target_node}" "${url_check}")" || http_code="0"
  
  if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "302" ]]; then
    bt_log_info "Post-restore verification passed: site responds with HTTP ${http_code}"
  else
    bt_log_warn "Post-restore verification warning: site responded with HTTP ${http_code}"
  fi
  
  bt_log_info "Post-restore tasks completed"
}
