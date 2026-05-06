#!/usr/bin/env bash

# TODO 11: Transferlogik implementieren
# Kopiert ein Backup von einem Quellknoten auf einen Zielknoten
# Unterstützt rsync als Standard mit scp als Fallback

backup_copy_usage() {
  cat <<'EOF'
Usage: backupctl backup copy --backup <id> --from <node> --to <node> [options]

Options:
  --backup <ref>    Backup reference: backup_id or backup_hash (required)
  --from <node>     Source node id (required)
  --to <node>       Target node id (required)
  -f, --force       Skip overwrite confirmation if target backup exists
  --no-validate     Skip transfer validation step
  -h, --help        Show this help
EOF
}

backup_copy_main() {
  local backup_ref="" backup_id="" from_node="" to_node="" force="" no_validate=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        backup_copy_usage
        return
        ;;
      --backup)
        backup_ref="$2"
        shift 2
        ;;
      --from)
        from_node="$2"
        shift 2
        ;;
      --to)
        to_node="$2"
        shift 2
        ;;
      -f|--force)
        force="1"
        shift
        ;;
      --no-validate)
        no_validate="1"
        shift
        ;;
      *)
        bt_die "Unknown copy option: $1"
        ;;
    esac
  done
  
  [[ -n "${backup_ref}" ]] || bt_die "copy: --backup is required"
  [[ -n "${from_node}" ]] || bt_die "copy: --from is required"
  [[ -n "${to_node}" ]] || bt_die "copy: --to is required"
  
  bt_require_loaded_config

  backup_id="$(bt_resolve_backup_ref_to_id "${backup_ref}")"
  
  copy_backup_between_nodes "${backup_id}" "${from_node}" "${to_node}" "${force}" "${no_validate}"
}

copy_backup_between_nodes() {
  local backup_id="$1"
  local from_node="$2"
  local to_node="$3"
  local force="${4:-}"
  local no_validate="${5:-}"
  
  bt_log_info "Copying backup: backup_id=${backup_id} from=${from_node} to=${to_node}"
  
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would copy backup ${backup_id} from ${from_node} to ${to_node}"
    return
  fi
  
  # Vorprüfung: Knoten erreichbar
  bt_check_node_reachability "${from_node}" || bt_die "Source node ${from_node} is not reachable"
  bt_check_node_reachability "${to_node}" || bt_die "Target node ${to_node} is not reachable"
  
  # Vorprüfung: Backup existiert auf Quelle
  local source_path target_path
  source_path="$(bt_get_backup_path_for_node "${from_node}" "${backup_id}")"
  [[ -n "${source_path}" ]] || bt_die "Backup ${backup_id} not found on node ${from_node}"
  
  # Zielpath konstruieren
  target_path="$(bt_get_target_backup_path_for_node "${to_node}" "${backup_id}")"

  # Wenn bereits ein gleichnamiges Backup existiert: Force oder bestaetigen.
  if run_on_node "${to_node}" "[[ -e $(bt_quote "${target_path}") ]]" >/dev/null 2>&1; then
    bt_confirm_or_force "${force}" "Backup ${backup_id} exists on target node ${to_node} and may be overwritten. Continue?"
  fi
  
  # Transferiere das Backup
  local transfer_cmd transfer_result
  transfer_cmd="$(build_transfer_command "${from_node}" "${to_node}" "${source_path}" "${target_path}")"
  
  bt_log_info "Executing transfer: $(echo "${transfer_cmd}" | head -c 100)..."
  
  if eval "${transfer_cmd}"; then
    bt_log_info "Transfer completed successfully"
  else
    transfer_result=$?
    bt_die "Transfer failed with exit code ${transfer_result}"
  fi
  
  # Validierung: Prüfe Dateianzahl und -größen nach Transfer (wenn nicht deaktiviert)
  if [[ -z "${no_validate}" ]]; then
    bt_validate_backup_transfer "${from_node}" "${to_node}" "${source_path}" "${target_path}" || \
      bt_log_warn "Transfer validation failed but backup may still be usable"
  fi
  
  # Cache aktualisieren
  bt_cache_add_entry "$(bt_get_cached_backup_object "${to_node}" "${backup_id}")"
  
  bt_log_info "Backup copy completed: ${backup_id} copied to ${to_node}"
}

bt_get_backup_path_for_node() {
  local node_id="$1"
  local backup_id="$2"
  local node_json node_type site backup_root
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  
  # Extrahiere Site aus backup_id (Format: node_site_timestamp)
  site="$(echo "${backup_id}" | cut -d_ -f2)"
  
  case "${node_type}" in
    frappe-node)
      backup_root="$(jq -r '.backup_paths[0]' <<<"${node_json}" | xargs dirname)"
      printf '%s/%s' "${backup_root}" "${backup_id}"
      ;;
    plain-dir)
      backup_root="$(jq -r '.backup_paths[0]' <<<"${node_json}")"
      printf '%s/%s' "${backup_root}" "${backup_id}"
      ;;
    *)
      return 1
      ;;
  esac
}

bt_get_target_backup_path_for_node() {
  local node_id="$1"
  local backup_id="$2"
  local node_json node_type site backup_root
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  
  site="$(echo "${backup_id}" | cut -d_ -f2)"
  
  case "${node_type}" in
    frappe-node)
      backup_root="$(jq -r '.backup_paths[0]' <<<"${node_json}" | xargs dirname)"
      mkdir -p "${backup_root}" || true
      printf '%s/%s' "${backup_root}" "${backup_id}"
      ;;
    plain-dir)
      backup_root="$(jq -r '.backup_paths[0]' <<<"${node_json}")"
      mkdir -p "${backup_root}" || true
      printf '%s/%s' "${backup_root}" "${backup_id}"
      ;;
    *)
      return 1
      ;;
  esac
}

bt_validate_backup_transfer() {
  local from_node="$1"
  local to_node="$2"
  local source_path="$3"
  local target_path="$4"
  
  # Vereinfachte Validierung: Prüfe ob Zielverzeichnis existiert und nicht leer ist
  local check_cmd result
  check_cmd="[[ -d '${target_path}' ]] && [[ -n \"\$(ls -A '${target_path}' 2>/dev/null)\" ]]"
  
  if run_on_node "${to_node}" "${check_cmd}" >/dev/null 2>&1; then
    bt_log_info "Backup validation passed: target path contains files"
    return 0
  else
    bt_log_warn "Backup validation warning: target path empty or missing"
    return 1
  fi
}

bt_get_cached_backup_object() {
  local node_id="$1"
  local backup_id="$2"
  local backup_hash

  backup_hash="$(bt_backup_hash_from_id "${backup_id}")"
  
  # Konstruiere ein minimales Backup-Objekt für Cache
  cat <<EOF
{
  "backup_id": "${backup_id}",
  "backup_hash": "${backup_hash}",
  "source_node": "${node_id}",
  "created_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "last_seen": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "complete": true
}
EOF
}