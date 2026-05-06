#!/usr/bin/env bash

scan_usage() {
  cat <<'EOF'
Usage: backupctl node scan [--node <id>] [--live-check]

Options:
  --node <id>     Scan only a single configured node
                  (without --node, all configured nodes are scanned)
  --live-check    Reserved for optional real-state verification mode
  -h, --help      Show this help
EOF
}

bt_scan_print_human() {
  local backup_json="$1"
  local backup_hash backup_id node site node_type complete

  backup_hash="$(jq -r '.backup_hash // "------"' <<<"${backup_json}")"
  backup_id="$(jq -r '.backup_id // "?"' <<<"${backup_json}")"
  node="$(jq -r '.source_node // "?"' <<<"${backup_json}")"
  site="$(jq -r '.source_site // "?"' <<<"${backup_json}")"
  node_type="$(jq -r '.node_type // .source_kind // "?"' <<<"${backup_json}")"
  complete="$(jq -r '.complete' <<<"${backup_json}")"

  printf 'FOUND [%s] node=%s site=%s kind=%s complete=%s id=%s\n' \
    "${backup_hash}" "${node}" "${site}" "${node_type}" "${complete}" "${backup_id}"
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
    
    bt_scan_site_backups "${node_id}" "${site}" "${site_backup_dir}" "frappe-node"
  done
}

bt_scan_site_backups() {
  local node_id="$1"
  local site="$2"
  local backup_dir="$3"
  local node_type="$4"
  
  [[ -d "${backup_dir}" ]] || return 0
  
  local manifest_file db_file public_file private_file config_file backup_id id_suffix
  
  for manifest_file in "${backup_dir}"/manifest.json; do
    [[ -f "${manifest_file}" ]] || continue
    
    if jq -e . "${manifest_file}" >/dev/null 2>&1; then
      backup_id="$(jq -r '.backup_id' "${manifest_file}")"
      printf '%s\n' "$(jq -c '. + {"source_node": "'${node_id}'", "source_site": "'${site}'", "node_type": "'${node_type}'"}' "${manifest_file}")"
      return
    fi
  done
  
  local db_dump
  for db_dump in "${backup_dir}"/*-database.sql.gz "${backup_dir}"/*-database.sql; do
    [[ -f "${db_dump}" ]] && break
  done
  
  if [[ -f "${db_dump}" ]]; then
    # Stable ID: node + site + db stem (without -database.sql(.gz) suffix)
    id_suffix="$(basename "${db_dump}")"
    id_suffix="${id_suffix%-database.sql.gz}"
    id_suffix="${id_suffix%-database.sql}"
    backup_id="${node_id}_${site}_${id_suffix}"
    
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
      jq -c '. + {"source_node": "'${node_id}'", "source_site": "'${site}'", "node_type": "'${node_type}'"}'
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
      printf '%s\n' "$(jq -c '. + {"source_node": "'${node_id}'", "node_type": "plain-dir"}' "${manifest_file}")"
    fi
  done
}

bt_scan_remote_manifests() {
  local node_id="$1"
  local node_type="$2"
  local backup_root="$3"

  local remote_cmd manifest_paths manifest_path manifest_json
  remote_cmd="if [[ -d $(bt_quote "${backup_root}") ]]; then find $(bt_quote "${backup_root}") -type f -name manifest.json; fi"
  manifest_paths="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS= read -r manifest_path; do
    [[ -n "${manifest_path}" ]] || continue

    manifest_json="$(run_on_node "${node_id}" "cat $(bt_quote "${manifest_path}")" 2>/dev/null || true)"
    [[ -n "${manifest_json}" ]] || continue

    if jq -e . >/dev/null 2>&1 <<<"${manifest_json}"; then
      jq -c --arg node "${node_id}" --arg nt "${node_type}" \
        '. + {source_node: $node, node_type: $nt}' <<<"${manifest_json}"
    fi
  done <<<"${manifest_paths}"
}

bt_scan_remote_frappe_without_manifest() {
  local node_id="$1"
  local backup_root="$2"

  local remote_cmd db_paths db_path
  remote_cmd="if [[ -d $(bt_quote "${backup_root}") ]]; then find $(bt_quote "${backup_root}") -type f \\( -name '*-database.sql.gz' -o -name '*-database.sql' \\) ; fi"
  db_paths="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS= read -r db_path; do
    [[ -n "${db_path}" ]] || continue

    local backup_dir site_dir site manifest_in_dir
    backup_dir="$(dirname "${db_path}")"
    site_dir="$(dirname "$(dirname "${backup_dir}")")"
    site="$(basename "${site_dir}")"
    manifest_in_dir="${backup_dir}/manifest.json"

    # If manifest exists, the manifest scan already indexes this backup.
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${manifest_in_dir}") ]]" >/dev/null 2>&1; then
      continue
    fi

    local db_file public_file private_file site_config_file artifacts_obj backup_id manifest_json
    db_file="$(basename "${db_path}")"
    public_file="${db_file/-database.sql.gz/-files.tar}"
    public_file="${public_file/-database.sql/-files.tar}"
    private_file="${db_file/-database.sql.gz/-private-files.tar}"
    private_file="${private_file/-database.sql/-private-files.tar}"
    site_config_file="${site_dir}/site_config.json"

    artifacts_obj="{\"db_dump\":\"${db_file}\"}"

    if run_on_node "${node_id}" "[[ -f $(bt_quote "${backup_dir}/${public_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c --arg f "${public_file}" '. + {public_files: $f}' <<<"${artifacts_obj}")"
    fi
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${backup_dir}/${private_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c --arg f "${private_file}" '. + {private_files: $f}' <<<"${artifacts_obj}")"
    fi
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${site_config_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c '. + {site_config: "site_config.json"}' <<<"${artifacts_obj}")"
    fi

    # Stable ID: node + site + db stem (without -database.sql(.gz) suffix)
    local id_suffix
    id_suffix="${db_file%-database.sql.gz}"
    id_suffix="${id_suffix%-database.sql}"
    backup_id="${node_id}_${site}_${id_suffix}"
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "remote frappe backup (without manifest)" "${artifacts_obj}")"

    if ! jq -e '.artifacts | has("site_config")' >/dev/null 2>&1 <<<"${manifest_json}"; then
      manifest_json="$(jq -c '.complete = false' <<<"${manifest_json}")"
    fi

    printf '%s\n' "${manifest_json}" | jq -c '. + {source_node: .source_node, source_site: .source_site, node_type: "frappe-node"}'
  done <<<"${db_paths}"
}

bt_scan_remote_plain_without_manifest() {
  local node_id="$1"
  local backup_root="$2"

  # Discover backup groups in a single remote pass to avoid one SSH roundtrip per artifact probe.
  local remote_cmd scan_rows scan_row
  remote_cmd="if [[ -d $(bt_quote "${backup_root}") ]]; then
find $(bt_quote "${backup_root}") -type f \\( -name '*site_config_backup.json' -o -name '*site_config.json' \\) -print0 |
while IFS= read -r -d '' site_config_path; do
  backup_dir=\"\$(dirname \"\${site_config_path}\")\"
  site_config_name=\"\$(basename \"\${site_config_path}\")\"
  manifest_in_dir=\"\${backup_dir}/manifest.json\"
  [[ -f \"\${manifest_in_dir}\" ]] && continue

  prefix=''
  case \"\${site_config_name}\" in
    *-site_config_backup.json)
      prefix=\"\${site_config_name%-site_config_backup.json}\"
      ;;
    *-site_config.json)
      prefix=\"\${site_config_name%-site_config.json}\"
      ;;
  esac

  db_path=''
  if [[ -n \"\${prefix}\" && -f \"\${backup_dir}/\${prefix}-database.sql.gz\" ]]; then
    db_path=\"\${backup_dir}/\${prefix}-database.sql.gz\"
  elif [[ -n \"\${prefix}\" && -f \"\${backup_dir}/\${prefix}-database.sql\" ]]; then
    db_path=\"\${backup_dir}/\${prefix}-database.sql\"
  else
    db_path=\"\$(find \"\${backup_dir}\" -maxdepth 1 -type f \\( -name '*-database.sql.gz' -o -name '*-database.sql' \\) | head -n 1)\"
  fi

  [[ -n \"\${db_path}\" ]] || continue

  db_file=\"\$(basename \"\${db_path}\")\"
  public_file=\"\${db_file/-database.sql.gz/-files.tar}\"
  public_file=\"\${public_file/-database.sql/-files.tar}\"
  private_file=\"\${db_file/-database.sql.gz/-private-files.tar}\"
  private_file=\"\${private_file/-database.sql/-private-files.tar}\"
  rel_dir=\"\${backup_dir#$(bt_quote "${backup_root}")/}\"
  [[ \"\${rel_dir}\" == \"\${backup_dir}\" ]] && rel_dir=\"\$(basename \"\${backup_dir}\")\"

  public_present=''
  private_present=''
  [[ -f \"\${backup_dir}/\${public_file}\" ]] && public_present=\"\${public_file}\"
  [[ -f \"\${backup_dir}/\${private_file}\" ]] && private_present=\"\${private_file}\"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    \"\${rel_dir}\" \
    \"\${site_config_name}\" \
    \"\${db_file}\" \
    \"\${public_present}\" \
    \"\${private_present}\"
done
fi"
  scan_rows="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS=$'\t' read -r rel_dir site_config_name db_file public_file private_file; do
    [[ -n "${db_file}" ]] || continue

    local artifacts_obj backup_id source_site logical_site manifest_json

    artifacts_obj="{\"db_dump\":\"${db_file}\",\"site_config\":\"${site_config_name}\"}"
    if [[ -n "${public_file}" ]]; then
      artifacts_obj="$(jq -c --arg f "${public_file}" '. + {public_files: $f}' <<<"${artifacts_obj}")"
    fi
    if [[ -n "${private_file}" ]]; then
      artifacts_obj="$(jq -c --arg f "${private_file}" '. + {private_files: $f}' <<<"${artifacts_obj}")"
    fi

    local id_suffix
    id_suffix="${db_file%-database.sql.gz}"
    id_suffix="${id_suffix%-database.sql}"

    source_site="${rel_dir}/${db_file}"
    logical_site="$(sed 's/[^a-zA-Z0-9._-]/_/g' <<<"${rel_dir}")"
    backup_id="${node_id}_${logical_site}_${id_suffix}"
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${source_site}" "remote plain backup (without manifest; inferred from site_config+db)" "${artifacts_obj}")"

    printf '%s\n' "${manifest_json}" | jq -c --arg rel_dir "${rel_dir}" '. + {source_node: .source_node, source_site: .source_site, node_type: "plain-dir", source_rel_dir: $rel_dir}'
  done <<<"${scan_rows}"
}

bt_scan_check_node_availability() {
  local node_id="$1"
  local node_json access container bench_path_val
  local available=0

  node_json="$(bt_get_node_json "${node_id}")"
  access="$(jq -r '.access' <<<"${node_json}")"
  container="$(jq -r '.container // empty' <<<"${node_json}")"
  bench_path_val="$(jq -r '.bench_path // empty' <<<"${node_json}")"

  # 1. SSH / docker-daemon reachability (early exit on failure)
  case "${access}" in
    ssh|ssh-docker)
      local ssh_host ssh_base
      ssh_host="$(jq -r '.ssh_config' <<<"${node_json}")"
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      if ! eval "${ssh_base} true" >/dev/null 2>&1; then
        bt_log_warn "Node ${node_id}: SSH host unreachable (${ssh_host})"
        return 1
      fi
      ;;
    docker)
      if ! bt_run_with_timeout "${BT_DOCKER_TIMEOUT_SEC:-10}" docker ps >/dev/null 2>&1; then
        bt_log_warn "Node ${node_id}: Docker daemon not reachable"
        return 1
      fi
      ;;
  esac

  # 2. Container running check (inspected from the host, not exec'd into it)
  if [[ -n "${container}" ]]; then
    local container_running
    case "${access}" in
      docker)
        local ctx
        ctx="$(bt_docker_local_context "${node_json}")"
        container_running="$(bt_run_with_timeout "${BT_DOCKER_TIMEOUT_SEC:-10}" docker --context "${ctx}" inspect --format '{{.State.Running}}' "${container}" 2>/dev/null || echo 'missing')"
        ;;
      ssh-docker)
        local ssh_base check_cmd
        ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
        check_cmd="docker inspect --format '{{.State.Running}}' $(bt_quote "${container}") 2>/dev/null || echo missing"
        container_running="$(eval "${ssh_base} $(bt_quote "${check_cmd}")" 2>/dev/null || echo 'missing')"
        ;;
    esac
    if [[ "${container_running}" != "true" ]]; then
      bt_log_warn "Node ${node_id}: Container '${container}' is not running (state: ${container_running:-unknown})"
      available=1
    fi
  fi

  # If container unavailable, path checks inside it will also fail — skip them
  if [[ "${available}" -ne 0 ]]; then
    return "${available}"
  fi

  # 3. backup_paths existence
  local bp
  while IFS= read -r bp; do
    [[ -z "${bp}" ]] && continue
    if ! run_on_node "${node_id}" "[[ -d $(bt_quote "${bp}") ]]" >/dev/null 2>&1; then
      bt_log_warn "Node ${node_id}: backup_path not accessible: ${bp}"
      available=1
    fi
  done < <(jq -r '.backup_paths[]' <<<"${node_json}")

  # 4. bench_path existence (if configured)
  if [[ -n "${bench_path_val}" ]]; then
    if ! run_on_node "${node_id}" "[[ -d $(bt_quote "${bench_path_val}") ]]" >/dev/null 2>&1; then
      bt_log_warn "Node ${node_id}: bench_path not accessible: ${bench_path_val}"
      available=1
    fi
  fi

  return "${available}"
}

bt_scan_collect_node_backups() {
  local node_id="$1"
  local collected_backups='[]'
  local backup_json

  while IFS= read -r backup_json; do
    [[ -z "${backup_json}" ]] && continue
    backup_json="$(bt_backup_with_hash "${backup_json}")"
    collected_backups="$(jq --argjson entry "${backup_json}" '. + [$entry]' <<<"${collected_backups}")"
  done < <(scan_node "${node_id}")

  printf '%s\n' "${collected_backups}"
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

  local _scan_and_cache
  _scan_and_cache() {
    local nid="$1"
    local found=0
    local collected_backups backup_json

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" ]]; then
      if ! bt_scan_check_node_availability "${nid}"; then
        bt_log_warn "Node ${nid}: scan skipped (cache not updated)"
        printf 'WARN  [------] node=%s unavailable\n' "${nid}"
        return 0
      fi
    fi

    collected_backups="$(bt_scan_collect_node_backups "${nid}")"
    found="$(jq 'length' <<<"${collected_backups}")"

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" ]]; then
      bt_cache_replace_node_backups "${nid}" "${collected_backups}"
    fi

    while IFS= read -r backup_json; do
      [[ -z "${backup_json}" ]] && continue
      bt_scan_print_human "${backup_json}"
    done < <(jq -c '.[]' <<<"${collected_backups}")

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" && ${found} -eq 0 ]]; then
      printf 'FOUND [------] node=%s none\n' "${nid}"
    fi
  }

  if [[ -z "${node_id}" ]]; then
    local nid
    for nid in $(bt_list_node_ids); do
      _scan_and_cache "${nid}"
    done
  else
    _scan_and_cache "${node_id}"
  fi
}

scan_node() {
  local node_id="$1"
  local node_json
  local node_type access backup_paths
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  access="$(jq -r '.access' <<<"${node_json}")"
  backup_paths="$(jq -r '.backup_paths[]' <<<"${node_json}")"
  
  local path
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue

    local path_results=""
    
    if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
      bt_log_info "Would scan: ${node_id} ${path} (${node_type})"
      continue
    fi

    case "${access}" in
      ssh|ssh-docker|docker)
        path_results="$({
          bt_scan_remote_manifests "${node_id}" "${node_type}" "${path}"
          case "${node_type}" in
            frappe-node)
              bt_scan_remote_frappe_without_manifest "${node_id}" "${path}"
              ;;
            plain-dir)
              bt_scan_remote_plain_without_manifest "${node_id}" "${path}"
              ;;
          esac
        } )"
        ;;
      local)
        case "${node_type}" in
          frappe-node)
            path_results="$(bt_scan_frappe_backup_dir "${node_id}" "${path}")"
            ;;
          plain-dir)
            path_results="$(bt_scan_plain_backup_dir "${node_id}" "${path}")"
            ;;
          *)
            bt_die "Unsupported node_type: ${node_type}"
            ;;
        esac
        ;;
      *)
        bt_die "Unsupported access for scan: ${access}"
        ;;
    esac

    if [[ -z "${path_results}" ]]; then
      bt_log_info "Node ${node_id}: found backup dir ${path}, but it is empty"
      continue
    fi

    printf '%s\n' "${path_results}"
  done <<<"${backup_paths}"
}
