#!/usr/bin/env bash

scan_usage() {
  cat <<'EOF'
Usage: backupctl scan [--node <id>] [--live-check]

Options:
  --node <id>     Scan only a single configured node
  --live-check    Reserved for optional real-state verification mode
  -h, --help      Show this help
EOF
}

bt_scan_frappe_backup_dir() {
  local node_id="$1"
  local backup_root="$2"
  
  [[ -d "${backup_root}" ]] || return 0
  
  local site_backup_dir
  for site_backup_dir in "${backup_root}"/*; do
    [[ -d "${site_backup_dir}" ]] || continue
    
    local site
    site="$(basename "${site_backup_dir}")"
    
    bt_scan_site_backups "${node_id}" "${site}" "${site_backup_dir}" "frappe-backup-dir"
  done
}

bt_scan_site_backups() {
  local node_id="$1"
  local site="$2"
  local backup_dir="$3"
  local source_kind="$4"
  
  [[ -d "${backup_dir}" ]] || return 0
  
  local manifest_file db_file public_file private_file config_file backup_id
  
  for manifest_file in "${backup_dir}"/manifest.json; do
    [[ -f "${manifest_file}" ]] || continue
    
    if jq -e . "${manifest_file}" >/dev/null 2>&1; then
      backup_id="$(jq -r '.backup_id' "${manifest_file}")"
      printf '%s\n' "$(jq -c '. + {"source_node": "'${node_id}'", "source_site": "'${site}'", "source_kind": "'${source_kind}'"}' "${manifest_file}")"
      return
    fi
  done
  
  local db_dump
  for db_dump in "${backup_dir}"/*-database.sql.gz "${backup_dir}"/*-database.sql; do
    [[ -f "${db_dump}" ]] && break
  done
  
  if [[ -f "${db_dump}" ]]; then
    backup_id="$(bt_generate_backup_id "${node_id}" "${site}")"
    
    local artifacts_obj
    artifacts_obj="{\"db_dump\": \"$(basename "${db_dump}")\"}"
    
    if [[ -f "${backup_dir}"/*-files.tar ]]; then
      artifacts_obj="$(jq -c '. + {"public_files": "'$(basename "${backup_dir}"/*-files.tar)'"}' <<<"${artifacts_obj}")"
    fi
    if [[ -f "${backup_dir}"/*-private-files.tar ]]; then
      artifacts_obj="$(jq -c '. + {"private_files": "'$(basename "${backup_dir}"/*-private-files.tar)'"}' <<<"${artifacts_obj}")"
    fi
    if [[ -f "${backup_dir}"/site_config.json ]]; then
      artifacts_obj="$(jq -c '. + {"site_config": "site_config.json"}' <<<"${artifacts_obj}")"
    fi
    
    bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "standard frappe backup" "${artifacts_obj}" | \
      jq -c '. + {"source_node": "'${node_id}'", "source_site": "'${site}'", "source_kind": "'${source_kind}'"}'
  fi
}

bt_scan_plain_backup_dir() {
  local node_id="$1"
  local backup_root="$2"
  
  [[ -d "${backup_root}" ]] || return 0
  
  local manifest_file
  for manifest_file in "${backup_root}"/*/manifest.json; do
    [[ -f "${manifest_file}" ]] || continue
    
    if jq -e . "${manifest_file}" >/dev/null 2>&1; then
      printf '%s\n' "$(jq -c '. + {"source_node": "'${node_id}'", "source_kind": "plain-backup-dir"}' "${manifest_file}")"
    fi
  done
}

scan_main() {
  local node_id=""
  local live_check=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        scan_usage
        return
        ;;
      --node)
        node_id="$2"
        shift 2
        ;;
      --live-check)
        live_check=1
        shift
        ;;
      *)
        bt_die "Unknown scan option: $1"
        ;;
    esac
  done
  
  bt_require_loaded_config
  
  if [[ -z "${node_id}" ]]; then
    local nid
    for nid in $(bt_list_node_ids); do
      scan_node "${nid}"
    done
  else
    scan_node "${node_id}"
  fi
}

scan_node() {
  local node_id="$1"
  local node_json
  local source_kind access_type backup_paths
  
  node_json="$(bt_get_node_json "${node_id}")"
  source_kind="$(jq -r '.source_kind' <<<"${node_json}")"
  backup_paths="$(jq -r '.backup_paths[]' <<<"${node_json}")"
  
  local path
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    
    if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
      bt_log_info "Would scan: ${node_id} ${path} (${source_kind})"
      continue
    fi
    
    case "${source_kind}" in
      frappe-backup-dir)
        bt_scan_frappe_backup_dir "${node_id}" "${path}"
        ;;
      plain-backup-dir)
        bt_scan_plain_backup_dir "${node_id}" "${path}"
        ;;
      *)
        bt_die "Unsupported source_kind: ${source_kind}"
        ;;
    esac
  done <<<"${backup_paths}"
}
