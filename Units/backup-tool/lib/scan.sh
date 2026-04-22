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

bt_scan_print_human() {
  local backup_json="$1"
  local backup_hash backup_id node site source_kind complete

  backup_hash="$(jq -r '.backup_hash // "------"' <<<"${backup_json}")"
  backup_id="$(jq -r '.backup_id // "?"' <<<"${backup_json}")"
  node="$(jq -r '.source_node // "?"' <<<"${backup_json}")"
  site="$(jq -r '.source_site // "?"' <<<"${backup_json}")"
  source_kind="$(jq -r '.source_kind // "?"' <<<"${backup_json}")"
  complete="$(jq -r '.complete' <<<"${backup_json}")"

  printf 'FOUND [%s] node=%s site=%s kind=%s complete=%s id=%s\n' \
    "${backup_hash}" "${node}" "${site}" "${source_kind}" "${complete}" "${backup_id}"
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
    # Stable ID: node + site + db filename (db filename contains timestamp)
    backup_id="${node_id}_${site}_$(basename "${db_dump}")"
    
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

bt_scan_remote_manifests() {
  local node_id="$1"
  local source_kind="$2"
  local backup_root="$3"

  local remote_cmd manifest_paths manifest_path manifest_json
  remote_cmd="if [[ -d $(bt_quote "${backup_root}") ]]; then find $(bt_quote "${backup_root}") -type f -name manifest.json; fi"
  manifest_paths="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS= read -r manifest_path; do
    [[ -n "${manifest_path}" ]] || continue

    manifest_json="$(run_on_node "${node_id}" "cat $(bt_quote "${manifest_path}")" 2>/dev/null || true)"
    [[ -n "${manifest_json}" ]] || continue

    if jq -e . >/dev/null 2>&1 <<<"${manifest_json}"; then
      jq -c --arg node "${node_id}" --arg sk "${source_kind}" \
        '. + {source_node: $node, source_kind: $sk}' <<<"${manifest_json}"
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

    # Stable ID: node + site + db filename (db filename already contains backup timestamp)
    backup_id="${node_id}_${site}_${db_file}"
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "remote frappe backup (without manifest)" "${artifacts_obj}")"

    if ! jq -e '.artifacts | has("site_config")' >/dev/null 2>&1 <<<"${manifest_json}"; then
      manifest_json="$(jq -c '.complete = false' <<<"${manifest_json}")"
    fi

    printf '%s\n' "${manifest_json}" | jq -c '. + {source_node: .source_node, source_site: .source_site, source_kind: "frappe-backup-dir"}'
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

    source_site="${rel_dir}/${db_file}"
    logical_site="$(sed 's/[^a-zA-Z0-9._-]/_/g' <<<"${source_site}")"
    backup_id="${node_id}_${logical_site}"
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${source_site}" "remote plain backup (without manifest; inferred from site_config+db)" "${artifacts_obj}")"

    printf '%s\n' "${manifest_json}" | jq -c --arg rel_dir "${rel_dir}" '. + {source_node: .source_node, source_site: .source_site, source_kind: "plain-backup-dir", source_rel_dir: $rel_dir}'
  done <<<"${scan_rows}"
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
  local source_kind access_type backup_paths
  
  node_json="$(bt_get_node_json "${node_id}")"
  source_kind="$(jq -r '.source_kind' <<<"${node_json}")"
  access_type="$(jq -r '.access_type' <<<"${node_json}")"
  backup_paths="$(jq -r '.backup_paths[]' <<<"${node_json}")"
  
  local path
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    
    if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
      bt_log_info "Would scan: ${node_id} ${path} (${source_kind})"
      continue
    fi

    case "${access_type}" in
      ssh-host|ssh-docker)
        bt_scan_remote_manifests "${node_id}" "${source_kind}" "${path}"
        case "${source_kind}" in
          frappe-backup-dir)
            bt_scan_remote_frappe_without_manifest "${node_id}" "${path}"
            ;;
          plain-backup-dir)
            bt_scan_remote_plain_without_manifest "${node_id}" "${path}"
            ;;
        esac
        ;;
      local|local-docker)
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
        ;;
      *)
        bt_die "Unsupported access_type for scan: ${access_type}"
        ;;
    esac
  done <<<"${backup_paths}"
}
