#!/usr/bin/env bash

backup_remove_usage() {
  cat <<'EOF'
Usage: backupctl backup remove --backup <id> [options]

Options:
  --backup <ref>    Backup reference: backup_id or backup_hash (required)
  -f, --force       Skip confirmation prompt
  --cache-only      Remove only cache entry, do not delete remote files
  -h, --help        Show this help
EOF
}

backup_remove_main() {
  local backup_ref="" backup_id="" force="" cache_only=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        backup_remove_usage
        return
        ;;
      --backup)
        backup_ref="$2"
        shift 2
        ;;
      -f|--force)
        force="1"
        shift
        ;;
      --cache-only)
        cache_only="1"
        shift
        ;;
      *)
        bt_die "Unknown remove option: $1"
        ;;
    esac
  done

  [[ -n "${backup_ref}" ]] || bt_die "remove: --backup is required"

  bt_require_loaded_config
  local backup_entry
  backup_entry="$(bt_resolve_backup_ref_to_entry "${backup_ref}")"
  backup_id="$(jq -r '.backup_id // empty' <<<"${backup_entry}")"
  [[ -n "${backup_id}" ]] || bt_die "remove: backup reference could not be resolved: ${backup_ref}"

  remove_backup_entry "${backup_entry}" "${force}" "${cache_only}"
}

bt_backup_remote_base_dir() {
  local backup_entry_json="$1"
  local node_id node_type source_site source_rel_dir node_json backup_root bench_path rel_dir

  node_id="$(jq -r '.source_node' <<<"${backup_entry_json}")"
  node_type="$(jq -r '.node_type // empty' <<<"${backup_entry_json}")"
  source_site="$(jq -r '.source_site // empty' <<<"${backup_entry_json}")"
  source_rel_dir="$(jq -r '.source_rel_dir // empty' <<<"${backup_entry_json}")"
  backup_root="$(jq -r '.backup_path // empty' <<<"${backup_entry_json}")"

  case "${node_type}" in
    frappe-node)
      if [[ -n "${backup_root}" ]]; then
        bt_join_backup_root_rel_dir "${backup_root}" "${source_rel_dir}"
      else
        bench_path="$(bt_node_bench_path "${node_id}")"
        printf '%s\n' "${bench_path}/sites/${source_site}/private/backups"
      fi
      ;;
    plain-dir)
      node_json="$(bt_get_node_json "${node_id}")"
      [[ -n "${backup_root}" ]] || backup_root="$(jq -r '.backup_path // empty' <<<"${node_json}")"
      [[ -n "${backup_root}" ]] || bt_die "remove: no backup_path configured for plain-dir node ${node_id}"

      if [[ -n "${source_rel_dir}" ]]; then
        rel_dir="${source_rel_dir}"
      elif [[ -n "${source_site}" && "${source_site}" == */* ]]; then
        rel_dir="$(dirname "${source_site}")"
      else
        rel_dir=""
      fi

      if [[ -n "${rel_dir}" && "${rel_dir}" != "." ]]; then
        printf '%s\n' "${backup_root}/${rel_dir}"
      else
        printf '%s\n' "${backup_root}"
      fi
      ;;
    *)
      bt_die "remove: unsupported or missing node_type for backup"
      ;;
  esac
}

bt_backup_artifact_file_list() {
  local backup_entry_json="$1"

  jq -r '
    .artifacts // {}
    | [ .db_dump, .public_files, .private_files, .site_config, .manifest, .checksums, .apps ]
    | map(select(type == "string" and length > 0))
    | .[]
  ' <<<"${backup_entry_json}" | awk '!seen[$0]++'
}

bt_cache_remove_backup_id() {
  local backup_id="$1"
  local entry_json node_id node_entries updated_entries

  entry_json="$(bt_cache_get_by_backup_id "${backup_id}" 2>/dev/null || true)"
  [[ -n "${entry_json}" && "${entry_json}" != "null" ]] || return 1

  node_id="$(jq -r '.source_node' <<<"${entry_json}")"
  node_entries="$(bt_cache_node_entries "${node_id}")"
  updated_entries="$(jq --arg bid "${backup_id}" '[ .[] | select(.backup_id != $bid) ]' <<<"${node_entries}")"

  bt_cache_replace_node_entries "${node_id}" "${updated_entries}"
}

remove_backup_by_id() {
  local backup_id="$1"
  local force="${2:-}"
  local cache_only="${3:-}"
  local entry_json

  entry_json="$(bt_cache_get_by_backup_id "${backup_id}" 2>/dev/null || true)"
  [[ -n "${entry_json}" && "${entry_json}" != "null" ]] || bt_die "remove: backup not found in cache: ${backup_id}"

  remove_backup_entry "${entry_json}" "${force}" "${cache_only}"
}

remove_backup_entry() {
  local entry_json="$1"
  local force="${2:-}"
  local cache_only="${3:-}"
  local backup_id node_id base_dir file_list file

  backup_id="$(jq -r '.backup_id // empty' <<<"${entry_json}")"
  node_id="$(jq -r '.source_node' <<<"${entry_json}")"
  bt_confirm_or_force "${force}" "Remove backup ${backup_id} on node ${node_id}?"

  if [[ -n "${cache_only}" ]]; then
    if bt_cache_remove_backup_id "${backup_id}"; then
      bt_log_info "Backup removed from cache: ${backup_id}"
      return
    fi
    bt_die "remove: failed to remove backup from cache: ${backup_id}"
  fi

  base_dir="$(bt_backup_remote_base_dir "${entry_json}")"
  file_list="$(bt_backup_artifact_file_list "${entry_json}" || true)"

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would remove backup files on node ${node_id} from ${base_dir}"
    if [[ -n "${file_list}" ]]; then
      while IFS= read -r file; do
        [[ -n "${file}" ]] || continue
        bt_log_info "Would remove: ${base_dir}/${file}"
      done <<<"${file_list}"
    fi
    bt_log_info "Would remove backup from cache: ${backup_id}"
    return
  fi

  bt_check_node_reachability "${node_id}" || bt_die "remove: source node ${node_id} is not reachable"

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue

    if [[ "${file}" = /* ]]; then
      run_on_node "${node_id}" "rm -f -- $(bt_quote "${file}")" >/dev/null 2>&1 || true
    else
      run_on_node "${node_id}" "rm -f -- $(bt_quote "${base_dir}/${file}")" >/dev/null 2>&1 || true
    fi
  done <<<"${file_list}"

  if bt_cache_remove_backup_id "${backup_id}"; then
    bt_log_info "Backup removed: ${backup_id}"
    return
  fi

  bt_die "remove: failed to remove backup from cache: ${backup_id}"
}
