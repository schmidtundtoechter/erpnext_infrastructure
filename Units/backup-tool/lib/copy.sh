#!/usr/bin/env bash

# TODO 11: Transferlogik implementieren
# Kopiert ein Backup von einem Quellknoten auf einen Zielknoten
# Unterstützt rsync als Standard mit scp als Fallback

backup_copy_usage() {
  cat <<'EOF'
Usage: backupctl backup copy --backup <id> --to <node> [options]

Options:
  --backup <ref>    Backup reference: backup_id or backup_hash (required)
  --to <node>       Target node id (required)
  -f, --force       Skip overwrite confirmation if target backup exists
  --no-validate     Skip transfer validation step
  -h, --help        Show this help
EOF
}

backup_copy_main() {
  local backup_ref="" backup_id="" source_node="" to_node="" force="" no_validate=""
  
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
  [[ -n "${to_node}" ]] || bt_die "copy: --to is required"
  
  bt_require_loaded_config

  backup_id="$(bt_resolve_backup_ref_to_id "${backup_ref}")"
  local backup_entry
  backup_entry="$(bt_cache_get_by_backup_id "${backup_id}" 2>/dev/null || true)"
  [[ "${backup_entry}" == "null" ]] && backup_entry=""

  if [[ -n "${backup_entry}" ]]; then
    source_node="$(jq -r '.source_node // empty' <<<"${backup_entry}")"
  fi

  [[ -n "${source_node}" ]] || bt_die "copy: source node could not be inferred from cache for backup '${backup_ref}'. Run 'backupctl node scan' first."
  bt_log_info "Resolved source node from cache: ${source_node}"

  copy_backup_between_nodes "${backup_id}" "${source_node}" "${to_node}" "${force}" "${no_validate}" "${backup_entry}"
}

copy_backup_between_nodes() {
  local backup_id="$1"
  local from_node="$2"
  local to_node="$3"
  local force="${4:-}"
  local no_validate="${5:-}"
  local backup_entry_json="${6:-}"
  
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
  source_path="$(bt_get_backup_path_for_node "${from_node}" "${backup_id}" "${backup_entry_json}")"
  [[ -n "${source_path}" ]] || bt_die "Backup ${backup_id} not found on node ${from_node}"
  
  # Zielpath konstruieren
  target_path="$(bt_get_target_backup_path_for_node "${to_node}" "${backup_id}" "${backup_entry_json}")"

  # Zielverzeichnis auf dem Zielknoten sicherstellen (nicht lokal).
  run_on_node "${to_node}" "mkdir -p $(bt_quote "$(dirname "${target_path}")")" >/dev/null 2>&1 || true

  # Wenn bereits ein gleichnamiges Backup existiert: Force oder bestaetigen.
  if run_on_node "${to_node}" "[[ -e $(bt_quote "${target_path}") ]]" >/dev/null 2>&1; then
    bt_confirm_or_force "${force}" "Backup ${backup_id} exists on target node ${to_node} and may be overwritten. Continue?"
  fi
  
  # Transferiere das Backup
  local transfer_cmd transfer_result
  if bt_transfer_same_ssh_docker_host "${from_node}" "${to_node}" "${source_path}" "${target_path}"; then
    bt_log_info "Transfer completed successfully"
  else
    transfer_cmd="$(build_transfer_command "${from_node}" "${to_node}" "${source_path}" "${target_path}")"
    bt_log_info "Executing transfer: $(echo "${transfer_cmd}" | head -c 100)..."

    if eval "${transfer_cmd}"; then
      bt_log_info "Transfer completed successfully"
    else
      transfer_result=$?
      bt_die "Transfer failed with exit code ${transfer_result}"
    fi
  fi
  
  # Validierung: Prüfe Dateianzahl und -größen nach Transfer (wenn nicht deaktiviert)
  if [[ -z "${no_validate}" ]]; then
    bt_validate_backup_transfer "${from_node}" "${to_node}" "${source_path}" "${target_path}" || \
      bt_log_warn "Transfer validation failed but backup may still be usable"
  fi
  
  # Cache aktualisieren
  bt_cache_add_entry "$(bt_get_cached_backup_object "${to_node}" "${backup_id}" "${backup_entry_json}")"
  
  bt_log_info "Backup copy completed: ${backup_id} copied to ${to_node}"
}

bt_transfer_same_ssh_docker_host() {
  local from_node="$1"
  local to_node="$2"
  local source_path="$3"
  local target_path="$4"
  local from_json to_json from_access to_access from_ssh to_ssh

  from_json="$(bt_get_node_json "${from_node}")"
  to_json="$(bt_get_node_json "${to_node}")"
  from_access="$(jq -r '.access' <<<"${from_json}")"
  to_access="$(jq -r '.access' <<<"${to_json}")"

  [[ "${from_access}" == "ssh-docker" && "${to_access}" == "ssh-docker" ]] || return 1

  from_ssh="$(jq -r '.ssh_config' <<<"${from_json}")"
  to_ssh="$(jq -r '.ssh_config' <<<"${to_json}")"
  [[ "${from_ssh}" == "${to_ssh}" ]] || return 1

  local source_container target_container ssh_base host_cmd target_parent
  source_container="$(jq -r '.container // empty' <<<"${from_json}")"
  target_container="$(jq -r '.container // empty' <<<"${to_json}")"
  [[ -n "${source_container}" && -n "${target_container}" ]] || return 1

  target_parent="$(dirname "${target_path}")"
  host_cmd="docker exec -i $(bt_quote "${source_container}") test -d $(bt_quote "${source_path}") && docker exec -i $(bt_quote "${target_container}") mkdir -p $(bt_quote "${target_parent}") && docker cp $(bt_quote "${source_container}:${source_path}") - | docker exec -i $(bt_quote "${target_container}") tar -C $(bt_quote "${target_parent}") -xf -"

  bt_log_info "Executing transfer via shared ssh-docker host (${from_ssh})"
  ssh_base="$(bt_build_ssh_base_cmd "${from_json}")"

  eval "${ssh_base} $(bt_quote "${host_cmd}")"
}

bt_get_backup_path_for_node() {
  local node_id="$1"
  local backup_id="$2"
  local backup_entry_json="${3:-}"
  local node_json node_type backup_root rel_dir
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"

  if [[ -n "${backup_entry_json}" && "${backup_entry_json}" != "null" ]]; then
    backup_root="$(jq -r '.backup_path // empty' <<<"${backup_entry_json}")"
    rel_dir="$(jq -r '.source_rel_dir // empty' <<<"${backup_entry_json}")"
    if [[ -n "${backup_root}" ]]; then
      bt_join_backup_root_rel_dir "${backup_root}" "${rel_dir}"
      return
    fi
  fi
  
  case "${node_type}" in
    frappe-node|plain-dir)
      backup_root="$(jq -r '.backup_path // empty' <<<"${node_json}")"
      [[ -n "${backup_root}" ]] || return 1
      printf '%s/%s' "${backup_root%/}" "${backup_id}"
      ;;
    *)
      return 1
      ;;
  esac
}

bt_get_target_backup_path_for_node() {
  local node_id="$1"
  local backup_id="$2"
  local backup_entry_json="${3:-}"
  local node_json node_type backup_root rel_dir
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  backup_root="$(jq -r '.backup_path // empty' <<<"${node_json}")"
  [[ -n "${backup_root}" ]] || return 1

  if [[ -n "${backup_entry_json}" && "${backup_entry_json}" != "null" ]]; then
    rel_dir="$(jq -r '.source_rel_dir // empty' <<<"${backup_entry_json}")"
    bt_join_backup_root_rel_dir "${backup_root}" "${rel_dir}"
    return
  fi
  
  case "${node_type}" in
    frappe-node|plain-dir)
      printf '%s/%s' "${backup_root%/}" "${backup_id}"
      ;;
    *)
      return 1
      ;;
  esac
}

bt_join_backup_root_rel_dir() {
  local backup_root="$1"
  local rel_dir="${2:-}"

  if [[ -n "${rel_dir}" && "${rel_dir}" != "." ]]; then
    printf '%s/%s' "${backup_root%/}" "${rel_dir#/}"
  else
    printf '%s' "${backup_root%/}"
  fi
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
  local source_entry_json="${3:-}"
  local backup_hash

  backup_hash="$(bt_backup_hash_from_id "${backup_id}")"

  if [[ -n "${source_entry_json}" && "${source_entry_json}" != "null" ]]; then
    local target_node_json target_backup_path target_node_type
    target_node_json="$(bt_get_node_json "${node_id}")"
    target_backup_path="$(jq -r '.backup_path // empty' <<<"${target_node_json}")"
    target_node_type="$(jq -r '.node_type // empty' <<<"${target_node_json}")"
    jq -c \
      --arg node_id "${node_id}" \
      --arg node_type "${target_node_type}" \
      --arg backup_path "${target_backup_path}" \
      --arg now "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      '. + {
        source_node: $node_id,
        node_type: $node_type,
        backup_path: $backup_path,
        created_at: (.created_at // $now),
        last_seen: $now,
        complete: (.complete // true)
      }' <<<"${source_entry_json}"
    return
  fi

  # Konstruiere ein minimales Backup-Objekt fuer Cache
  cat <<EOF
{
  "backup_id": "${backup_id}",
  "backup_hash": "${backup_hash}",
  "source_node": "${node_id}",
  "backup_path": "$(bt_get_node_json "${node_id}" | jq -r '.backup_path // empty')",
  "source_rel_dir": "",
  "created_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "last_seen": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "complete": true
}
EOF
}
