#!/usr/bin/env bash

declare -g BT_CACHE_DIR="${BT_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/backupctl}"
declare -g BT_CACHE_NODES_DIR="${BT_CACHE_NODES_DIR:-${BT_CACHE_DIR}/nodes}"
declare -g BT_CACHE_LEGACY_PATH="${BT_CACHE_LEGACY_PATH:-${BT_CACHE_DIR}/cache.jsonl}"
declare -g BT_CACHE_SCAN_STATE_PATH="${BT_CACHE_SCAN_STATE_PATH:-${BT_CACHE_DIR}/scan-state.json}"

bt_cache_init() {
  [[ -d "${BT_CACHE_DIR}" ]] || mkdir -p "${BT_CACHE_DIR}"
  [[ -d "${BT_CACHE_NODES_DIR}" ]] || mkdir -p "${BT_CACHE_NODES_DIR}"
}

bt_cache_node_file_token() {
  local node_id="$1"

  jq -rn -r --arg s "${node_id}" '$s | @uri'
}

bt_cache_node_path() {
  local node_id="$1"

  printf '%s/%s.json' "${BT_CACHE_NODES_DIR}" "$(bt_cache_node_file_token "${node_id}")"
}

bt_cache_scan_state_all() {
  bt_cache_init

  if [[ -s "${BT_CACHE_SCAN_STATE_PATH}" ]]; then
    jq -c . "${BT_CACHE_SCAN_STATE_PATH}"
  else
    printf '{}\n'
  fi
}

bt_cache_replace_scan_state_all() {
  local states_json="$1"
  local tmp_path

  bt_cache_init
  tmp_path="${BT_CACHE_SCAN_STATE_PATH}.tmp"

  jq '.' <<<"${states_json}" > "${tmp_path}"
  mv "${tmp_path}" "${BT_CACHE_SCAN_STATE_PATH}"
}

bt_cache_node_backup_count() {
  local node_id="$1"
  local node_entries

  node_entries="$(bt_cache_node_entries "${node_id}")"
  jq 'length' <<<"${node_entries}"
}

bt_cache_node_last_seen() {
  local node_id="$1"
  local node_entries

  node_entries="$(bt_cache_node_entries "${node_id}")"
  jq -r 'if length == 0 then "" else (map(.last_seen // "") | map(select(. != "")) | sort | last // "") end' <<<"${node_entries}"
}

bt_cache_upsert_scan_state() {
  local node_id="$1"
  local reachable="$2"
  local backups="$3"
  local cache_status="$4"
  local last_scan_at="${5:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  local states_json updated_states

  states_json="$(bt_cache_scan_state_all)"
  updated_states="$(jq -c \
    --arg node_id "${node_id}" \
    --arg reachable "${reachable}" \
    --arg cache_status "${cache_status}" \
    --arg last_scan_at "${last_scan_at}" \
    --argjson backups "${backups}" \
    '. + {($node_id): {reachable: $reachable, backups: $backups, cache_status: $cache_status, last_scan_at: $last_scan_at}}' <<<"${states_json}")"

  bt_cache_replace_scan_state_all "${updated_states}"
}

bt_cache_scan_state_rows_json() {
  bt_require_loaded_config

  local states_json rows_json node_id backup_count state_json last_scan_at reachable cache_status
  rows_json='[]'
  states_json="$(bt_cache_scan_state_all)"

  while IFS= read -r node_id; do
    [[ -n "${node_id}" ]] || continue

    backup_count="$(bt_cache_node_backup_count "${node_id}")"
    state_json="$(jq -c --arg node_id "${node_id}" '.[$node_id] // {}' <<<"${states_json}")"
    last_scan_at="$(jq -r '.last_scan_at // empty' <<<"${state_json}")"
    if [[ -z "${last_scan_at}" ]]; then
      last_scan_at="$(bt_cache_node_last_seen "${node_id}")"
    fi
    [[ -n "${last_scan_at}" ]] || last_scan_at='-'

    reachable="$(jq -r '.reachable // "-"' <<<"${state_json}")"
    cache_status="$(jq -r '.cache_status // empty' <<<"${state_json}")"
    if [[ -z "${cache_status}" ]]; then
      if [[ "${backup_count}" -gt 0 ]]; then
        cache_status='cached'
      else
        cache_status='not-scanned'
      fi
    fi

    rows_json="$(jq -c \
      --arg node "${node_id}" \
      --arg reachable "${reachable}" \
      --arg last_scan_at "${last_scan_at}" \
      --arg cache_status "${cache_status}" \
      --argjson backups "${backup_count}" \
      '. + [{node: $node, reachable: $reachable, backups: $backups, last_scan_at: $last_scan_at, cache_status: $cache_status}]' <<<"${rows_json}")"
  done < <(bt_list_node_ids)

  printf '%s\n' "${rows_json}"
}

bt_cache_entries_with_scan_state() {
  local entries_json="$1"
  local states_json

  states_json="$(bt_cache_scan_state_all)"

  jq -c --argjson states "${states_json}" '
    map(
      . + {
        last_scan_at: ($states[.source_node].last_scan_at // .last_seen // "-"),
        node_reachable: ($states[.source_node].reachable // "-"),
        node_cache_status: ($states[.source_node].cache_status // "cached")
      }
    )
  ' <<<"${entries_json}"
}

bt_cache_has_node_files() {
  bt_cache_init
  compgen -G "${BT_CACHE_NODES_DIR}/*.json" >/dev/null 2>&1
}

bt_cache_prune_removed_node_files() {
  bt_cache_init
  bt_require_loaded_config

  local expected_files=""
  local node_id
  while IFS= read -r node_id; do
    [[ -n "${node_id}" ]] || continue
    expected_files+="$(basename "$(bt_cache_node_path "${node_id}")")"$'\n'
  done < <(bt_list_node_ids)

  local cache_file cache_name
  for cache_file in "${BT_CACHE_NODES_DIR}"/*.json; do
    [[ -e "${cache_file}" ]] || break
    cache_name="$(basename "${cache_file}")"
    if ! grep -Fxq "${cache_name}" <<<"${expected_files}"; then
      rm -f "${cache_file}"
    fi
  done

  if [[ -f "${BT_CACHE_LEGACY_PATH}" ]]; then
    rm -f "${BT_CACHE_LEGACY_PATH}"
  fi
}

bt_cache_node_entries() {
  local node_id="$1"
  local node_path

  bt_cache_init
  node_path="$(bt_cache_node_path "${node_id}")"

  if [[ -s "${node_path}" ]]; then
    jq -c . "${node_path}"
  else
    printf '[]\n'
  fi
}

bt_cache_replace_node_entries() {
  local node_id="$1"
  local entries_json="$2"
  local node_path tmp_path

  bt_cache_init
  node_path="$(bt_cache_node_path "${node_id}")"
  tmp_path="${node_path}.tmp"

  jq '.' <<<"${entries_json}" > "${tmp_path}"
  mv "${tmp_path}" "${node_path}"
  if [[ -f "${BT_CACHE_LEGACY_PATH}" ]]; then
    rm -f "${BT_CACHE_LEGACY_PATH}"
  fi
}

bt_cache_replace_node_backups() {
  local node_id="$1"
  local backups_json="$2"
  local timestamp cache_entries

  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cache_entries="$(jq --arg last_seen "${timestamp}" '[ .[] + {last_seen: $last_seen} ]' <<<"${backups_json}")"

  bt_cache_replace_node_entries "${node_id}" "${cache_entries}"
}

bt_cache_entry_schema() {
  cat <<'EOM'
Cache Entry (per-node pretty JSON arrays):
[
  {
    "backup_id": "string (required)",
    "source_node": "string (required)",
    "node_type": "string (required)",
    "source_site": "string (required)",
    "backup_path": "string (required, configured node backup_path used during scan)",
    "source_rel_dir": "string (required, backup directory relative to backup_path)",
    "reason": "string (required)",
    "tags": "array (optional)",
    "created_at": "string ISO 8601 (required)",
    "file_count": "integer (optional)",
    "total_size": "integer in bytes (optional)",
    "complete": "boolean (required)",
    "last_seen": "string ISO 8601 (required)"
  }
]
EOM
}

bt_cache_build_entry() {
  local backup_obj_json="$1"
  local timestamp="$2"

  jq -n \
    --argjson backup "${backup_obj_json}" \
    --arg last_seen "${timestamp}" \
    '$backup + {last_seen: $last_seen}'
}

bt_cache_add_entry() {
  local backup_obj_json="$1"

  bt_cache_upsert_entry "${backup_obj_json}"
}

bt_cache_get_by_backup_id() {
  local backup_id="$1"
  local all_entries

  all_entries="$(bt_cache_list_all)"
  jq -e --arg bid "${backup_id}" 'map(select(.backup_id == $bid))[0]' <<<"${all_entries}"
}

bt_cache_get_by_backup_hash() {
  local backup_hash="$1"
  local all_entries

  all_entries="$(bt_cache_list_all)"
  jq -e --arg bh "${backup_hash}" 'map(select(.backup_hash == $bh))[0]' <<<"${all_entries}"
}

bt_resolve_backup_ref_to_entry() {
  local backup_ref="$1"
  local all_entries by_id_count by_hash_count

  all_entries="$(bt_cache_list_all)"
  by_id_count="$(jq --arg bid "${backup_ref}" 'map(select(.backup_id == $bid)) | length' <<<"${all_entries}")"
  by_hash_count="$(jq --arg bh "${backup_ref}" 'map(select(.backup_hash == $bh)) | length' <<<"${all_entries}")"

  if [[ "${by_hash_count}" -gt 1 ]]; then
    bt_die "Backup hash '${backup_ref}' is ambiguous (${by_hash_count} matches). Run 'backupctl node scan' to refresh location hashes."
  fi

  if [[ "${by_hash_count}" -eq 1 ]]; then
    jq -c --arg bh "${backup_ref}" 'map(select(.backup_hash == $bh))[0]' <<<"${all_entries}"
    return
  fi

  if [[ "${by_id_count}" -gt 1 ]]; then
    bt_die "Backup id '${backup_ref}' has multiple copies (${by_id_count} matches). Use backup_hash."
  fi

  if [[ "${by_id_count}" -eq 1 ]]; then
    jq -c --arg bid "${backup_ref}" 'map(select(.backup_id == $bid))[0]' <<<"${all_entries}"
    return
  fi

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    jq -nc --arg bid "${backup_ref}" '{backup_id: $bid}'
    return
  fi

  bt_die "Backup reference not found in cache: ${backup_ref}. Run 'backupctl node scan' first."
}

bt_resolve_backup_ref_to_id() {
  local backup_ref="$1"
  local entry_json resolved_id

  entry_json="$(bt_resolve_backup_ref_to_entry "${backup_ref}")"
  resolved_id="$(jq -r '.backup_id // empty' <<<"${entry_json}")"
  [[ -n "${resolved_id}" ]] || bt_die "Invalid cache entry for backup reference: ${backup_ref}"
  printf '%s\n' "${resolved_id}"
}

bt_cache_list_all() {
  bt_cache_init
  bt_cache_prune_removed_node_files

  if ! bt_cache_has_node_files; then
    printf '[]\n'
    return
  fi

  jq -s 'add // []' "${BT_CACHE_NODES_DIR}"/*.json
}

bt_cache_filter() {
  local json_lines="$1"
  local node_filter="${2:-}"
  local site_filter="${3:-}"
  local tag_filter="${4:-}"
  local reason_contains="${5:-}"
  local complete_filter="${6:-}"
  local from_date="${7:-}"
  local to_date="${8:-}"
  
  local filter_expr='.'
  
  [[ -n "${node_filter}" ]] && filter_expr="${filter_expr} | select(.source_node == \"${node_filter}\")"
  [[ -n "${site_filter}" ]] && filter_expr="${filter_expr} | select(.source_site == \"${site_filter}\")"
  [[ -n "${tag_filter}" ]] && filter_expr="${filter_expr} | select(.tags | map(select(. == \"${tag_filter}\")) | length > 0)"
  [[ -n "${reason_contains}" ]] && filter_expr="${filter_expr} | select(.reason | contains(\"${reason_contains}\"))"
  [[ -n "${complete_filter}" ]] && filter_expr="${filter_expr} | select(.complete == ${complete_filter})"
  [[ -n "${from_date}" ]] && filter_expr="${filter_expr} | select(.created_at >= \"${from_date}\")"
  [[ -n "${to_date}" ]] && filter_expr="${filter_expr} | select(.created_at <= \"${to_date}\")"
  
  jq -c ".[] | ${filter_expr}" <<<"${json_lines}"
}

bt_cache_rebuild() {
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would rebuild cache in: ${BT_CACHE_DIR}"
    return
  fi

  bt_require_loaded_config
  bt_cache_clear

  local node_id
  for node_id in $(bt_list_node_ids); do
    bt_cache_replace_node_backups "${node_id}" "$(bt_scan_collect_node_backups "${node_id}")"
  done

  bt_log_info "Cache rebuilt: $(bt_cache_list_all | jq 'length') entries"
}

bt_cache_clear() {
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would clear cache in: ${BT_CACHE_DIR}"
    return
  fi

  bt_cache_init
  rm -f "${BT_CACHE_NODES_DIR}"/*.json 2>/dev/null || true
  rm -f "${BT_CACHE_LEGACY_PATH}" 2>/dev/null || true
  rm -f "${BT_CACHE_SCAN_STATE_PATH}" 2>/dev/null || true
  bt_log_info "Cache cleared"
}

bt_cache_upsert_entry() {
  local backup_json="$1"
  local normalized_entry
  local timestamp
  local node_id node_entries updated_entries

  bt_cache_init

  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  normalized_entry="$(bt_cache_build_entry "${backup_json}" "${timestamp}")"
  node_id="$(jq -r '.source_node' <<<"${normalized_entry}")"
  node_entries="$(bt_cache_node_entries "${node_id}")"
  updated_entries="$(jq --argjson entry "${normalized_entry}" '
    [ .[]
      | select(
          .backup_id != $entry.backup_id
          or (.backup_path // "") != ($entry.backup_path // "")
          or (.source_rel_dir // "") != ($entry.source_rel_dir // "")
        )
    ] + [ $entry ]
  ' <<<"${node_entries}")"

  bt_cache_replace_node_entries "${node_id}" "${updated_entries}"
}

bt_cache_update_incremental() {
  local node_id="$1"

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would update cache for node: ${node_id}"
    return
  fi

  bt_cache_replace_node_backups "${node_id}" "$(bt_scan_collect_node_backups "${node_id}")"
}

cache_clear_main() {
  bt_cache_clear
}
