#!/usr/bin/env bash

# TODO 12-14: Restore implementieren mit site_config.json Handling und Nacharbeiten

backup_restore_usage() {
  cat <<'EOF'
Usage: backupctl backup restore --backup <id> --to <node> --site <site> [options]

Options:
  --backup <id>                              Backup id (required)
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
  local backup_id="" target_node="" target_site="" config_mode="merge-config" \
    dry_run="" force="" no_checks=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        backup_restore_usage
        return
        ;;
      --backup)
        backup_id="$2"
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
  
  [[ -n "${backup_id}" ]] || bt_die "restore: --backup is required"
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
  
  # Hole Backup-Pfad
  local backup_path
  backup_path="$(bt_get_backup_path_for_node "${target_node}" "${backup_id}")" || \
    bt_die "Backup ${backup_id} not found on target node"
  
  # Extrahiere Dateien aus Backup
  local db_dump public_files private_files config_file
  db_dump="${backup_path}/latest-database.sql.gz"
  public_files="${backup_path}/latest-files.tar"
  private_files="${backup_path}/latest-private-files.tar"
  config_file="${backup_path}/site_config.json"
  
  # Handle site_config.json gemäß config_mode
  if [[ "${config_mode}" == "merge-config" ]] || [[ "${config_mode}" == "keep-target-config" ]]; then
    bt_handle_site_config_merge "${backup_id}" "${target_node}" "${target_site}" \
      "${config_file}" "${config_mode}"
  fi
  
  # Führe bench restore aus
  local bench_cmd
  bench_cmd="cd /home/frappe/frappe-bench && bench --site ${target_site} restore ${db_dump}"
  
  bt_log_info "Executing bench restore for site ${target_site}..."
  run_on_node "${target_node}" "${bench_cmd}" || bt_die "Bench restore failed"
  
  # Restore Files wenn vorhanden
  if run_on_node "${target_node}" "[[ -f ${public_files} ]]" >/dev/null 2>&1; then
    bt_restore_files_to_site "${target_node}" "${target_site}" "${public_files}" "public"
  fi
  
  if run_on_node "${target_node}" "[[ -f ${private_files} ]]" >/dev/null 2>&1; then
    bt_restore_files_to_site "${target_node}" "${target_site}" "${private_files}" "private"
  fi
  
  # Post-Restore Aufgaben
  bt_execute_post_restore_tasks "${backup_id}" "${target_node}" "${target_site}"
  
  bt_log_info "Restore completed: ${backup_id} restored to ${target_site} on ${target_node}"
}

# TODO 13: Behandlung von site_config.json
bt_handle_site_config_merge() {
  local backup_id="$1"
  local target_node="$2"
  local target_site="$3"
  local source_config_file="$4"
  local config_mode="$5"
  
  bt_log_info "Handling site_config.json with mode: ${config_mode}"
  
  case "${config_mode}" in
    use-source-config)
      # Einfach Quelle verwenden
      bt_log_info "Using source site_config.json"
      ;;
    keep-target-config)
      # Zielkonfiguration bewahren
      bt_log_info "Keeping target site_config.json"
      return
      ;;
    merge-config)
      # Merge: Behalte zielspezifische Felder, übernehme nur allgemeine Felder
      bt_log_info "Merging site_config.json..."
      
      # Felder die NICHT von Quelle übernommen werden (sind zielspezifisch)
      local protected_fields=(
        "db_name"
        "db_password"
        "admin_password"
        "encryption_key"
        "file_watcher_port"
      )
      
      # Hole target-site-config
      local target_config_path get_cmd
      target_config_path="/home/frappe/frappe-bench/sites/${target_site}/site_config.json"
      get_cmd="cat ${target_config_path}"
      
      local target_config
      target_config="$(run_on_node "${target_node}" "${get_cmd}" 2>/dev/null || echo '{}')"
      
      # Merger Logik: Übernehme allgemeine Felder von Quelle, bewahre protected Fields vom Ziel
      local source_config merged_config
      source_config="$(run_on_node "${target_node}" "cat ${source_config_file}" 2>/dev/null || echo '{}')"
      
      # Baue merged config auf
      merged_config="{}"
      for field in $(echo "${source_config}" | jq -r 'keys[]' 2>/dev/null); do
        # Prüfe ob Feld protegiert ist
        local is_protected=0
        for protected in "${protected_fields[@]}"; do
          if [[ "${field}" == "${protected}" ]]; then
            is_protected=1
            break
          fi
        done
        
        if [[ $is_protected -eq 1 ]]; then
          # Bewahre Zielwert
          merged_config="$(jq -c ". + {\"${field}\": $(jq -c ".${field}" <<<"${target_config}")}" <<<"${merged_config}" 2>/dev/null)"
        else
          # Übernehme Quellwert
          merged_config="$(jq -c ". + {\"${field}\": $(jq -c ".${field}" <<<"${source_config}")}" <<<"${merged_config}" 2>/dev/null)"
        fi
      done
      
      # Schreibe gemergete config zurück
      echo "${merged_config}" | run_on_node "${target_node}" "cat > ${target_config_path}"
      bt_log_info "Site config merge completed"
      ;;
  esac
}

bt_restore_files_to_site() {
  local node_id="$1"
  local site="$2"
  local tar_file="$3"
  local file_type="$4"  # "public" oder "private"
  
  local extract_cmd site_path
  site_path="/home/frappe/frappe-bench/sites/${site}"
  
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
  
  bt_log_info "Executing post-restore tasks..."
  
  # 1. Bench-Migration wenn nötig
  local migration_cmd
  migration_cmd="cd /home/frappe/frappe-bench && bench migrate --site ${target_site}"
  run_on_node "${target_node}" "${migration_cmd}" || bt_log_warn "Bench migration failed (site may need manual attention)"
  
  # 2. Rechte und Dateipfade prüfen
  local fix_perms_cmd
  fix_perms_cmd="cd /home/frappe/frappe-bench && bench fix-permissions --user frappe"
  run_on_node "${target_node}" "${fix_perms_cmd}" || bt_log_warn "Fix permissions failed"
  
  # 3. Clear Cache
  local clear_cache_cmd
  clear_cache_cmd="cd /home/frappe/frappe-bench && bench --site ${target_site} clear-cache"
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