#!/usr/bin/env bash

backup_create_usage() {
  cat <<'EOF'
Usage: backupctl backup create --node <id> [--site <site>] [--reason <text>] [options]

Options:
  --node <id>           Source node id (required)
  --site <site>         Site name (auto-detected when exactly one site is known)
  --reason <text>       Business reason (default: manual backup create)
  --tag <tag>           Add tag (repeatable)
  --backup-type <type>  Backup type label (default: full-with-files)
  -h, --help            Show this help
EOF
}

bt_list_known_sites_for_node() {
  local node_id="$1"
  local cached_entries cached_sites bench_path sites_cmd discovered_sites

  cached_entries="$(bt_cache_node_entries "${node_id}" 2>/dev/null || printf '[]\n')"
  cached_sites="$(jq -r 'map(.source_site) | map(select(. != null and . != "")) | unique[]?' <<<"${cached_entries}" 2>/dev/null || true)"
  if [[ -n "${cached_sites}" ]]; then
    printf '%s\n' "${cached_sites}"
    return
  fi

  [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]] && return

  bench_path="$(bt_node_bench_path "${node_id}")"
  sites_cmd="find $(bt_quote "${bench_path}/sites") -mindepth 1 -maxdepth 1 -type d ! -name assets -exec basename {} \\; | sort -u"
  discovered_sites="$(run_on_node "${node_id}" "${sites_cmd}" 2>/dev/null || true)"
  [[ -n "${discovered_sites}" ]] && printf '%s\n' "${discovered_sites}"
}

bt_resolve_create_site() {
  local node_id="$1"
  local explicit_site="$2"
  local known_sites site_count

  if [[ -n "${explicit_site}" ]]; then
    printf '%s\n' "${explicit_site}"
    return
  fi

  known_sites="$(bt_list_known_sites_for_node "${node_id}")"
  site_count="$(sed '/^$/d' <<<"${known_sites}" | wc -l | tr -d ' ')"

  if [[ "${site_count}" == "1" ]]; then
    sed '/^$/d' <<<"${known_sites}" | head -n 1
    return
  fi

  if [[ "${site_count}" == "0" ]]; then
    bt_die "create: --site is required (no unique site could be detected for node ${node_id})"
  fi

  bt_die "create: --site is required (${site_count} sites detected for node ${node_id})"
}

backup_create_main() {
  local node_id="" site="" reason="manual backup create" tags_list="" backup_type="full-with-files"
  
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
  
  bt_require_loaded_config
  
  local node_json node_type
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  
  [[ "${node_type}" == "frappe-node" ]] || \
    bt_die "create: only frappe-node sources support backup creation"

  site="$(bt_resolve_create_site "${node_id}" "${site}")"
  
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
  
  local backup_id artifacts_obj tags_array bench_path
  # backup_id will be derived from the actual filename after bench runs; use a placeholder for now
  backup_id="${node_id}_${site}_$(date -u +%s)"

  tags_array="$(printf '[%s]\n' "$(printf '"%s",' ${tags_list} | sed 's/,$//g')")"
  
  bench_path="$(bt_node_bench_path "${node_id}")"

  local bench_cmd
  bench_cmd="cd $(bt_quote "${bench_path}") && bench --site ${site} backup --with-files"
  
  run_on_node "${node_id}" "${bench_cmd}" || bt_die "Backup creation failed"

  local backups_dir actual_db_file id_suffix
  backups_dir="${bench_path}/sites/${site}/private/backups"

  # Resolve the actual DB filename created by bench (newest non-symlink *.sql.gz, not latest-*)
  actual_db_file="$(run_on_node "${node_id}" \
    "find $(bt_quote "${backups_dir}") -maxdepth 1 -type f -name '*-database.sql.gz' ! -name 'latest-*' -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -n1 | awk '{print \$2}'" \
    2>/dev/null || true)"

  # Fallback: try without -printf (busybox/alpine)
  if [[ -z "${actual_db_file}" ]]; then
    actual_db_file="$(run_on_node "${node_id}" \
      "ls -t $(bt_quote "${backups_dir}")/*-database.sql.gz 2>/dev/null | grep -v 'latest-' | head -n1 | xargs -r basename" \
      2>/dev/null || true)"
  fi

  if [[ -n "${actual_db_file}" ]]; then
    id_suffix="${actual_db_file%-database.sql.gz}"
    backup_id="${node_id}_${site}_${id_suffix}"
  fi

  local public_files_src private_files_src
  public_files_src="${backups_dir}/${id_suffix}-files.tar"
  private_files_src="${backups_dir}/${id_suffix}-private-files.tar"

  artifacts_obj="{\"db_dump\":\"${actual_db_file:-latest-database.sql.gz}\"}"

  if [[ -n "${id_suffix}" ]] && run_on_node "${node_id}" "[[ -f $(bt_quote "${public_files_src}") ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c --arg f "${id_suffix}-files.tar" '. + {public_files: $f}' <<<"${artifacts_obj}")"
  elif run_on_node "${node_id}" "[[ -f $(bt_quote "${backups_dir}/latest-files.tar") ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c '. + {"public_files":"latest-files.tar"}' <<<"${artifacts_obj}")"
  fi

  if [[ -n "${id_suffix}" ]] && run_on_node "${node_id}" "[[ -f $(bt_quote "${private_files_src}") ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c --arg f "${id_suffix}-private-files.tar" '. + {private_files: $f}' <<<"${artifacts_obj}")"
  elif run_on_node "${node_id}" "[[ -f $(bt_quote "${backups_dir}/latest-private-files.tar") ]]" >/dev/null 2>&1; then
    artifacts_obj="$(jq -c '. + {"private_files":"latest-private-files.tar"}' <<<"${artifacts_obj}")"
  fi

  artifacts_obj="$(jq -c '. + {"site_config":"site_config.json"}' <<<"${artifacts_obj}")"

  local manifest_file
  if [[ -n "${id_suffix}" ]]; then
    manifest_file="${id_suffix}-manifest.json"
  else
    manifest_file="manifest.json"
  fi
  artifacts_obj="$(jq -c --arg f "${manifest_file}" '. + {manifest: $f}' <<<"${artifacts_obj}")"

  local manifest_json
  manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "${reason}" "${artifacts_obj}" "${tags_array}")"

  # Write manifest to the remote backup directory so the scan reads it back.
  # This makes reason/tags/artifacts persistent independent of the local cache.
  local remote_manifest_path="${backups_dir}/${manifest_file}"
  if run_on_node "${node_id}" "printf '%s\n' $(bt_quote "${manifest_json}") > $(bt_quote "${remote_manifest_path}")" >/dev/null 2>&1; then
    bt_log_info "Manifest written to remote: ${remote_manifest_path}"
  else
    bt_log_warn "Could not write manifest to remote: ${remote_manifest_path} (non-fatal)"
  fi

  bt_log_info "Backup created: ${backup_id}"
  
  if bt_cache_add_entry "${manifest_json}"; then
    bt_log_info "Cache updated with new backup"
  fi
  
  printf '%s\n' "${manifest_json}"
}
