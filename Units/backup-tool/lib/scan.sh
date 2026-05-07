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

bt_scan_epoch_to_iso8601() {
  local epoch="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "${epoch}" <<'PY'
from datetime import datetime, timezone
import sys

print(datetime.fromtimestamp(int(sys.argv[1]), timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
    return
  fi

  date -u -r "${epoch}" +"%Y-%m-%dT%H:%M:%SZ"
}

bt_scan_local_file_mtime_iso8601() {
  local file_path="$1"
  local epoch

  if epoch="$(stat -f '%m' "${file_path}" 2>/dev/null)"; then
    bt_scan_epoch_to_iso8601 "${epoch}"
    return
  fi

  if epoch="$(stat -c '%Y' "${file_path}" 2>/dev/null)"; then
    bt_scan_epoch_to_iso8601 "${epoch}"
    return
  fi

  printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

bt_scan_remote_file_mtime_iso8601() {
  local node_id="$1"
  local file_path="$2"
  local epoch

  epoch="$(run_on_node "${node_id}" "python3 -c $(bt_quote "import os, sys; print(int(os.path.getmtime(sys.argv[1])))") $(bt_quote "${file_path}")" 2>/dev/null || true)"
  if [[ -n "${epoch}" ]]; then
    bt_scan_epoch_to_iso8601 "${epoch}"
    return
  fi

  epoch="$(run_on_node "${node_id}" "stat -c %Y $(bt_quote "${file_path}")" 2>/dev/null || true)"
  if [[ -n "${epoch}" ]]; then
    bt_scan_epoch_to_iso8601 "${epoch}"
    return
  fi

  epoch="$(run_on_node "${node_id}" "stat -f %m $(bt_quote "${file_path}")" 2>/dev/null || true)"
  if [[ -n "${epoch}" ]]; then
    bt_scan_epoch_to_iso8601 "${epoch}"
    return
  fi

  printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

bt_scan_entry_with_location_hash() {
  local backup_json="$1"

  bt_backup_with_hash "${backup_json}"
}

bt_scan_update_local_manifest_hash() {
  local manifest_path="$1"
  local backup_json="$2"
  local new_hash old_hash tmp_path

  new_hash="$(jq -r '.backup_hash // empty' <<<"${backup_json}")"
  [[ -n "${new_hash}" ]] || return 0

  old_hash="$(jq -r '.backup_hash // empty' "${manifest_path}" 2>/dev/null || true)"
  [[ "${old_hash}" == "${new_hash}" ]] && return 0

  tmp_path="${manifest_path}.tmp.$$"
  if jq --arg h "${new_hash}" '. + {backup_hash: $h}' "${manifest_path}" > "${tmp_path}"; then
    mv "${tmp_path}" "${manifest_path}"
    bt_log_info "Updated manifest backup_hash: ${manifest_path}"
  else
    rm -f "${tmp_path}" 2>/dev/null || true
    bt_log_warn "Could not update manifest backup_hash: ${manifest_path}"
  fi
}

bt_scan_update_remote_manifest_hash() {
  local node_id="$1"
  local manifest_path="$2"
  local backup_json="$3"
  local new_hash update_script update_cmd

  new_hash="$(jq -r '.backup_hash // empty' <<<"${backup_json}")"
  [[ -n "${new_hash}" ]] || return 0

  update_script='import json, os, sys
path, backup_hash = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
if data.get("backup_hash") == backup_hash:
    raise SystemExit(0)
data["backup_hash"] = backup_hash
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=False)
    f.write("\n")
os.replace(tmp, path)'

  update_cmd="python3 -c $(bt_quote "${update_script}") $(bt_quote "${manifest_path}") $(bt_quote "${new_hash}")"
  if run_on_node "${node_id}" "${update_cmd}" >/dev/null 2>&1; then
    bt_log_info "Updated remote manifest backup_hash: ${node_id}:${manifest_path}"
  else
    bt_log_warn "Could not update remote manifest backup_hash: ${node_id}:${manifest_path}"
  fi
}

bt_scan_relative_dir() {
  local root="$1"
  local dir="$2"
  local rel_dir

  rel_dir="${dir#"${root%/}/"}"
  if [[ "${rel_dir}" == "${dir}" ]]; then
    # dir equals root: backup is directly at the root, no relative subdirectory
    rel_dir=""
  fi

  printf '%s\n' "${rel_dir}"
}

bt_scan_frappe_backup_dir() {
  local node_id="$1"
  local backup_root="$2"
  
  [[ -d "${backup_root}" ]] || return 0
  
  local db_dump backup_dir site_dir site rel_dir
  while IFS= read -r db_dump; do
    [[ -n "${db_dump}" ]] || continue

    backup_dir="$(dirname "${db_dump}")"
    site_dir="$(dirname "$(dirname "${backup_dir}")")"
    site="$(basename "${site_dir}")"
    rel_dir="$(bt_scan_relative_dir "${backup_root}" "${backup_dir}")"

    bt_scan_site_backups "${node_id}" "${site}" "${backup_dir}" "frappe-node" "${backup_root}" "${rel_dir}"
  done < <(find "${backup_root}" -type f \( -name '*-database.sql.gz' -o -name '*-database.sql' \) 2>/dev/null)
}

bt_scan_site_backups() {
  local node_id="$1"
  local site="$2"
  local backup_dir="$3"
  local node_type="$4"
  local backup_root="${5:-}"
  local rel_dir="${6:-}"
  
  [[ -d "${backup_dir}" ]] || return 0
  
  local manifest_file db_file public_file private_file config_file backup_id id_suffix created_at
  
  for manifest_file in "${backup_dir}"/manifest.json; do
    [[ -f "${manifest_file}" ]] || continue
    
    if jq -e . "${manifest_file}" >/dev/null 2>&1; then
      backup_id="$(jq -r '.backup_id' "${manifest_file}")"
      local backup_json
      backup_json="$(jq -c --arg mf "$(basename "${manifest_file}")" --arg bp "${backup_root}" --arg rel_dir "${rel_dir}" '.
        | .artifacts = ((.artifacts // {}) + (if ((.artifacts // {}) | has("manifest")) then {} else {manifest: $mf} end))
        | . + {"source_node": "'${node_id}'", "source_site": "'${site}'", "node_type": "'${node_type}'", "backup_path": $bp, "source_rel_dir": $rel_dir}' "${manifest_file}")"
      backup_json="$(bt_scan_entry_with_location_hash "${backup_json}")"
      bt_scan_update_local_manifest_hash "${manifest_file}" "${backup_json}"
      printf '%s\n' "${backup_json}"
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
    
    local artifact_file
    for artifact_file in "${backup_dir}"/*-files.tar; do
      [[ -f "${artifact_file}" ]] || continue
      [[ "$(basename "${artifact_file}")" == *-private-files.tar ]] && continue
      artifacts_obj="$(jq -c --arg f "$(basename "${artifact_file}")" '. + {public_files: $f}' <<<"${artifacts_obj}")"
      break
    done
    for artifact_file in "${backup_dir}"/*-private-files.tar; do
      [[ -f "${artifact_file}" ]] || continue
      artifacts_obj="$(jq -c --arg f "$(basename "${artifact_file}")" '. + {private_files: $f}' <<<"${artifacts_obj}")"
      break
    done
    
    # site_config wird von Frappe als *-site_config_backup.json gespeichert (oder plain site_config_backup.json)
    local site_config_found
    for artifact_file in "${backup_dir}"/*-site_config_backup.json; do
      [[ -f "${artifact_file}" ]] || continue
      artifacts_obj="$(jq -c --arg f "$(basename "${artifact_file}")" '. + {site_config: $f}' <<<"${artifacts_obj}")"
      site_config_found=1
      break
    done
    if [[ -z "${site_config_found}" ]] && [[ -f "${backup_dir}"/site_config_backup.json ]]; then
      artifacts_obj="$(jq -c '. + {"site_config": "site_config_backup.json"}' <<<"${artifacts_obj}")"
    fi
    
    created_at="$(bt_scan_local_file_mtime_iso8601 "${db_dump}")"

    bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "standard frappe backup" "${artifacts_obj}" '[]' "${created_at}" | \
      jq -c --arg bp "${backup_root}" --arg rel_dir "${rel_dir}" '. + {"source_node": "'${node_id}'", "source_site": "'${site}'", "node_type": "'${node_type}'", "backup_path": $bp, "source_rel_dir": $rel_dir}'
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
      local backup_dir rel_dir
      backup_dir="$(dirname "${manifest_file}")"
      rel_dir="$(bt_scan_relative_dir "${backup_root}" "${backup_dir}")"

      local backup_json
      backup_json="$(jq -c --arg mf "$(basename "${manifest_file}")" --arg bp "${backup_root}" --arg rel_dir "${rel_dir}" '.
        | .artifacts = ((.artifacts // {}) + (if ((.artifacts // {}) | has("manifest")) then {} else {manifest: $mf} end))
        | . + {"source_node": "'${node_id}'", "node_type": "plain-dir", "backup_path": $bp, "source_rel_dir": $rel_dir}' "${manifest_file}")"
      backup_json="$(bt_scan_entry_with_location_hash "${backup_json}")"
      bt_scan_update_local_manifest_hash "${manifest_file}" "${backup_json}"
      printf '%s\n' "${backup_json}"
    fi
  done
}

bt_scan_remote_manifests() {
  local node_id="$1"
  local node_type="$2"
  local backup_root="$3"

  local remote_cmd manifest_paths manifest_path manifest_json manifest_file
  remote_cmd="if [[ -d $(bt_quote "${backup_root}") ]]; then find $(bt_quote "${backup_root}") -type f \( -name 'manifest.json' -o -name '*-manifest.json' \); fi"
  manifest_paths="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS= read -r manifest_path; do
    [[ -n "${manifest_path}" ]] || continue
    manifest_file="$(basename "${manifest_path}")"

    manifest_json="$(run_on_node "${node_id}" "cat $(bt_quote "${manifest_path}")" 2>/dev/null || true)"
    [[ -n "${manifest_json}" ]] || continue

    if jq -e . >/dev/null 2>&1 <<<"${manifest_json}"; then
      local backup_dir rel_dir
      backup_dir="$(dirname "${manifest_path}")"
      rel_dir="${backup_dir#"${backup_root%/}/"}"
      [[ "${rel_dir}" == "${backup_dir}" ]] && rel_dir=""

      local backup_json
      backup_json="$(jq -c --arg mf "${manifest_file}" \
        '.artifacts = ((.artifacts // {}) + (if ((.artifacts // {}) | has("manifest")) then {} else {manifest: $mf} end))' \
        <<<"${manifest_json}")"
      backup_json="$(bt_manifest_add_node_meta "${backup_json}" "${node_id}" "${node_type}" "${backup_root}" "${backup_dir}")"
      backup_json="$(bt_scan_entry_with_location_hash "${backup_json}")"
      bt_scan_update_remote_manifest_hash "${node_id}" "${manifest_path}" "${backup_json}"
      printf '%s\n' "${backup_json}"
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

    local backup_dir site_dir site db_file id_suffix manifest_in_dir rel_dir
    backup_dir="$(dirname "${db_path}")"
    site_dir="$(dirname "$(dirname "${backup_dir}")")"
    site="$(basename "${site_dir}")"
    rel_dir="$(bt_scan_relative_dir "${backup_root}" "${backup_dir}")"
    db_file="$(basename "${db_path}")"
    id_suffix="${db_file%-database.sql.gz}"
    id_suffix="${id_suffix%-database.sql}"
    manifest_in_dir="${backup_dir}/${id_suffix}-manifest.json"

    # If a per-backup manifest exists, bt_scan_remote_manifests already indexes this backup.
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${manifest_in_dir}") ]]" >/dev/null 2>&1; then
      continue
    fi

    local public_file private_file site_config_file artifacts_obj backup_id manifest_json created_at
    # db_file and id_suffix already derived above (before manifest skip check)
    public_file="${db_file/-database.sql.gz/-files.tar}"
    public_file="${public_file/-database.sql/-files.tar}"
    private_file="${db_file/-database.sql.gz/-private-files.tar}"
    private_file="${private_file/-database.sql/-private-files.tar}"
    site_config_file="${db_file%-database.sql*}-site_config_backup.json"

    artifacts_obj="{\"db_dump\":\"${db_file}\"}"

    if run_on_node "${node_id}" "[[ -f $(bt_quote "${backup_dir}/${public_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c --arg f "${public_file}" '. + {public_files: $f}' <<<"${artifacts_obj}")"
    fi
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${backup_dir}/${private_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c --arg f "${private_file}" '. + {private_files: $f}' <<<"${artifacts_obj}")"
    fi
    if run_on_node "${node_id}" "[[ -f $(bt_quote "${backup_dir}/${site_config_file}") ]]" >/dev/null 2>&1; then
      artifacts_obj="$(jq -c --arg f "${site_config_file}" '. + {site_config: $f}' <<<"${artifacts_obj}")"
    fi

    # Stable ID: node + site + db stem (without -database.sql(.gz) suffix)
    backup_id="${node_id}_${site}_${id_suffix}"
    created_at="$(bt_scan_remote_file_mtime_iso8601 "${node_id}" "${db_path}")"
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${site}" "remote frappe backup (without manifest)" "${artifacts_obj}" '[]' "${created_at}")"

    if ! jq -e '.artifacts | has("site_config")' >/dev/null 2>&1 <<<"${manifest_json}"; then
      manifest_json="$(jq -c '.complete = false' <<<"${manifest_json}")"
    fi

    printf '%s\n' "${manifest_json}" | jq -c --arg bp "${backup_root}" --arg rel_dir "${rel_dir}" '. + {source_node: .source_node, source_site: .source_site, node_type: "frappe-node", backup_path: $bp, source_rel_dir: $rel_dir}'
  done <<<"${db_paths}"
}

bt_scan_remote_plain_without_manifest() {
  local node_id="$1"
  local backup_root="$2"

  # Discover backup groups in a single remote pass to avoid one SSH roundtrip per artifact probe.
  local remote_cmd scan_rows
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

  db_epoch=''
  db_epoch=\"\$(python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' \"\${db_path}\" 2>/dev/null || stat -c %Y \"\${db_path}\" 2>/dev/null || stat -f %m \"\${db_path}\" 2>/dev/null || true)\"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    \"\${rel_dir}\" \
    \"\${site_config_name}\" \
    \"\${db_file}\" \
    \"\${public_present}\" \
    \"\${private_present}\" \
    \"\${db_epoch}\"
done
fi"
  scan_rows="$(run_on_node "${node_id}" "${remote_cmd}" 2>/dev/null || true)"

  while IFS=$'\t' read -r rel_dir site_config_name db_file public_file private_file db_epoch; do
    [[ -n "${db_file}" ]] || continue

    local artifacts_obj backup_id source_site logical_site manifest_json created_at

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
    if [[ -n "${db_epoch}" ]]; then
      created_at="$(bt_scan_epoch_to_iso8601 "${db_epoch}")"
    else
      created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi
    manifest_json="$(bt_generate_manifest_json "${backup_id}" "${node_id}" "${source_site}" "remote plain backup (without manifest; inferred from site_config+db)" "${artifacts_obj}" '[]' "${created_at}")"

    printf '%s\n' "${manifest_json}" | jq -c --arg bp "${backup_root}" --arg rel_dir "${rel_dir}" '. + {source_node: .source_node, source_site: .source_site, node_type: "plain-dir", backup_path: $bp, source_rel_dir: $rel_dir}'
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

  # 3. backup_path existence
  local bp
  bp="$(jq -r '.backup_path // empty' <<<"${node_json}")"
  if [[ -n "${bp}" ]] && ! run_on_node "${node_id}" "[[ -d $(bt_quote "${bp}") ]]" >/dev/null 2>&1; then
    bt_log_warn "Node ${node_id}: backup_path not accessible: ${bp}"
    available=1
  fi

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

  bt_scan_print_reports() {
    bt_print_node_overview_table "Scan overview"
  }

  local _scan_and_cache
  _scan_and_cache() {
    local nid="$1"
    local found=0
    local collected_backups backup_json
    local reachable="yes"
    local cache_status="unchanged"

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" ]]; then
      if ! bt_scan_check_node_availability "${nid}"; then
        reachable="no"
        bt_log_warn "Node ${nid}: scan skipped (cache not updated)"
        printf 'WARN  [------] node=%s unavailable\n' "${nid}"
        bt_cache_upsert_scan_state "${nid}" "${reachable}" "0" "${cache_status}"
        return 0
      fi
    fi

    collected_backups="$(bt_scan_collect_node_backups "${nid}")"
    found="$(jq 'length' <<<"${collected_backups}")"

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" ]]; then
      bt_cache_replace_node_backups "${nid}" "${collected_backups}"
      cache_status="updated"
    else
      cache_status="dry-run"
    fi

    while IFS= read -r backup_json; do
      [[ -z "${backup_json}" ]] && continue
      bt_scan_print_human "${backup_json}"
    done < <(jq -c '.[]' <<<"${collected_backups}")

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" && ${found} -eq 0 ]]; then
      printf 'FOUND [------] node=%s none\n' "${nid}"
    fi

    if [[ "${BT_RUNNER_MODE:-execute}" != "dry-run" ]]; then
      bt_cache_upsert_scan_state "${nid}" "${reachable}" "${found}" "${cache_status}"
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

  bt_scan_print_reports
}

scan_node() {
  local node_id="$1"
  local node_json
  local node_type access backup_path
  
  node_json="$(bt_get_node_json "${node_id}")"
  node_type="$(jq -r '.node_type' <<<"${node_json}")"
  access="$(jq -r '.access' <<<"${node_json}")"
  backup_path="$(jq -r '.backup_path // empty' <<<"${node_json}")"
  
  local path
  path="${backup_path}"
  [[ -z "${path}" ]] && bt_die "Node ${node_id} has no backup_path configured"

  local path_results=""
    
    if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
      bt_log_info "Would scan: ${node_id} ${path} (${node_type})"
      return
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
      return
    fi

    printf '%s\n' "${path_results}"
}
