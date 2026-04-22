#!/usr/bin/env bash

backup_create_usage() {
  cat <<'EOF'
Usage: backupctl create --node <id> --site <site> --reason <text> [options]

Options:
  --node <id>           Source node id (required)
  --site <site>         Site name (required)
  --reason <text>       Business reason (required)
  --tag <tag>           Add tag (repeatable)
  --backup-type <type>  Backup type label (default: full-with-files)
  -h, --help            Show this help
EOF
}

backup_create_main() {
  local node_id="" site="" reason="" tags_list="" backup_type="full-with-files"
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        backup_create_usage
        return
        ;;
      --node)
        node_id="$2"
        shift 2
        ;;
      --site)
        site="$2"
        shift 2
        ;;
      --reason)
        reason="$2"
        shift 2
        ;;
      --tag)
        tags_list="${tags_list}$2 "
        shift 2
        ;;
      --backup-type)
        backup_type="$2"
        shift 2
        ;;
      *)
        bt_die "Unknown create option: $1"
        ;;
    esac
  done
  
  [[ -n "${node_id}" ]] || bt_die "create: --node is required"
  [[ -n "${site}" ]] || bt_die "create: --site is required"
  [[ -n "${reason}" ]] || bt_die "create: --reason is required"
  
  bt_require_loaded_config
  
  local node_json source_kind
  node_json="$(bt_get_node_json "${node_id}")"
  source_kind="$(jq -r '.source_kind' <<<"${node_json}")"
  
  [[ "${source_kind}" == "frappe-backup-dir" ]] || \
    bt_die "create: only frappe-backup-dir sources support backup creation"
  
  create_backup_on_node "${node_id}" "${site}" "${reason}" "${tags_list}" "${backup_type}"
}

create_backup_on_node() {
  local node_id="$1"
  local site="$2"
  local reason="$3"
  local tags_list="$4"
  local backup_type="$5"
  
  bt_log_info "Creating backup: node=${node_id} site=${site} reason=${reason}"
  
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would create backup on ${node_id} for site ${site}"
    return
  fi
  
  local backup_id backup_dir artifacts_obj tags_array
  backup_id="$(bt_generate_backup_id "${node_id}" "${site}")"
  backup_dir="/tmp/backupctl_${backup_id}"
  
  tags_array="$(printf '[%s]\n' "$(printf '"%s",' ${tags_list} | sed 's/,$//g')")"
  
  local bench_cmd
  bench_cmd="cd /home/frappe/frappe-bench && bench --site ${site} backup --with-files"
  
  run_on_node "${node_id}" "${bench_cmd}" || bt_die "Backup creation failed"
  
  local db_dump_src public_files_src private_files_src config_src
  
  db_dump_src="/home/frappe/frappe-bench/sites/${site}/private/backups/latest-database.sql.gz"
  public_files_src="/home/frappe/frappe-bench/sites/${site}/private/backups/latest-files.tar"
  private_files_src="/home/frappe/frappe-bench/sites/${site}/private/backups/latest-private-files.tar"
  config_src="/home/frappe/frappe-bench/sites/${site}/site_config.json"
  
  artifacts_obj="{\"db_dump\":\"$(basename "${db_dump_src}")\"}"
  
  if run_on_node "${node_id}" "[[ -f ${public_files_src} ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c '. + {"public_files":"'$(basename "${public_files_src}")'"}' <<<"${artifacts_obj}")"
  fi
  
  if run_on_node "${node_id}" "[[ -f ${private_files_src} ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c '. + {"private_files":"'$(basename "${private_files_src}")'"}' <<<"${artifacts_obj}")"
  fi
  
  artifacts_obj="$(jq -c '. + {"site_config":"site_config.json"}' <<<"${artifacts_obj}")"
  
  local manifest_json
  manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "${reason}" "${artifacts_obj}" "${tags_array}")"
  
  bt_log_info "Backup created: ${backup_id}"
  
  if bt_cache_add_entry "${manifest_json}"; then
    bt_log_info "Cache updated with new backup"
  fi
  
  printf '%s\n' "${manifest_json}"
}
