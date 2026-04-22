#!/usr/bin/env bash

declare -g BT_CACHE_PATH="${BT_CACHE_PATH:-${XDG_CACHE_HOME:-$HOME/.cache}/backupctl/cache.jsonl}"

bt_cache_init() {
  local cache_dir
  cache_dir="$(dirname "${BT_CACHE_PATH}")"
  [[ -d "${cache_dir}" ]] || mkdir -p "${cache_dir}"
  [[ -f "${BT_CACHE_PATH}" ]] || touch "${BT_CACHE_PATH}"
}

bt_cache_entry_schema() {
  cat <<'EOM'
Cache Entry (JSON Lines format):
{
  "backup_id": "string (required)",
  "source_node": "string (required)",
  "source_kind": "string (required)",
  "source_site": "string (required)",
  "reason": "string (required)",
  "tags": "array (optional)",
  "created_at": "string ISO 8601 (required)",
  "file_count": "integer (optional)",
  "total_size": "integer in bytes (optional)",
  "complete": "boolean (required)",
  "last_seen": "string ISO 8601 (required)"
}
EOM
}

bt_cache_add_entry() {
  local backup_obj_json="$1"
  local timestamp
  
  bt_cache_init
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  
  jq -n \
    --argjson backup "${backup_obj_json}" \
    --arg last_seen "${timestamp}" \
    '($backup | del(.source_kind)) + {last_seen: $last_seen}' >> "${BT_CACHE_PATH}"
}

bt_cache_get_by_backup_id() {
  local backup_id="$1"
  
  bt_cache_init
  grep -F "\"${backup_id}\"" "${BT_CACHE_PATH}" 2>/dev/null | jq -e ".backup_id == \"${backup_id}\"" >/dev/null && \
    grep -F "\"${backup_id}\"" "${BT_CACHE_PATH}" | jq -s '.[0]'
}

bt_cache_list_all() {
  bt_cache_init
  [[ -f "${BT_CACHE_PATH}" ]] && jq -s . "${BT_CACHE_PATH}"
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
  
  echo "${json_lines}" | jq -s ".[] | ${filter_expr}"
}

bt_cache_rebuild() {
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would rebuild cache: ${BT_CACHE_PATH}"
    return
  fi
  
  bt_cache_init
  > "${BT_CACHE_PATH}"
  
  bt_require_loaded_config
  local node_id
  for node_id in $(bt_list_node_ids); do
    scan_node "${node_id}" | while read -r backup_json; do
      [[ -z "${backup_json}" ]] && continue
      bt_cache_add_entry "${backup_json}"
    done
  done
  
  bt_log_info "Cache rebuilt: $(wc -l <"${BT_CACHE_PATH}") entries"
}

bt_cache_clear() {
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would clear cache: ${BT_CACHE_PATH}"
    return
  fi
  
  [[ -f "${BT_CACHE_PATH}" ]] && > "${BT_CACHE_PATH}"
  bt_log_info "Cache cleared"
}

bt_cache_update_incremental() {
  local node_id="$1"
  
  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    bt_log_info "Would update cache for node: ${node_id}"
    return
  fi
  
  bt_cache_init
  
  scan_node "${node_id}" | while read -r backup_json; do
    [[ -z "${backup_json}" ]] && continue
    local backup_id
    backup_id="$(jq -r '.backup_id' <<<"${backup_json}")"
    
    grep -v "\"${backup_id}\"" "${BT_CACHE_PATH}" > "${BT_CACHE_PATH}.tmp"
    mv "${BT_CACHE_PATH}.tmp" "${BT_CACHE_PATH}"
    
    bt_cache_add_entry "${backup_json}"
  done
}

cache_rebuild_main() {
  bt_cache_rebuild
}

cache_clear_main() {
  bt_cache_clear
}
