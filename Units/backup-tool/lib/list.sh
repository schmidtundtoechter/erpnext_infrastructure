#!/usr/bin/env bash

list_usage() {
  cat <<'EOF'
Usage: backupctl list [options]

Options:
  --format text|json        Output format (default: text)
  --node <id>               Filter by source node
  --site <site>             Filter by source site
  --tag <tag>               Filter by tag
  --reason-contains <text>  Filter by reason substring
  --complete true|false     Filter by completeness
  --from <iso8601>          Filter created_at >= from
  --to <iso8601>            Filter created_at <= to
  --live-check              Reserved for optional real-state verification mode
  -h, --help                Show this help
EOF
}

list_main() {
  local format="text" node_filter="" site_filter="" tag_filter="" reason_filter=""
  local complete_filter="" from_date="" to_date="" live_check=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        list_usage
        return
        ;;
      --format)
        format="$2"
        shift 2
        ;;
      --node)
        node_filter="$2"
        shift 2
        ;;
      --site)
        site_filter="$2"
        shift 2
        ;;
      --tag)
        tag_filter="$2"
        shift 2
        ;;
      --reason-contains)
        reason_filter="$2"
        shift 2
        ;;
      --complete)
        complete_filter="$2"
        shift 2
        ;;
      --from)
        from_date="$2"
        shift 2
        ;;
      --to)
        to_date="$2"
        shift 2
        ;;
      --live-check)
        live_check=1
        shift
        ;;
      *)
        bt_die "Unknown list option: $1"
        ;;
    esac
  done
  
  bt_cache_init
  bt_cache_has_node_files || bt_cache_rebuild
  
  local all_entries
  all_entries="$(bt_cache_list_all)"
  
  local filtered_entries
  filtered_entries="$(bt_cache_filter "${all_entries}" "${node_filter}" "${site_filter}" \
    "${tag_filter}" "${reason_filter}" "${complete_filter}" "${from_date}" "${to_date}")"
  
  case "${format}" in
    json)
      printf '%s\n' "${filtered_entries}" | jq -s .
      ;;
    text)
      bt_list_format_text "${filtered_entries}"
      ;;
    *)
      bt_die "Unknown list format: ${format}"
      ;;
  esac
}

bt_list_format_text() {
  local entries="$1"
  
  printf '%-40s %-20s %-30s %-15s %s\n' "BACKUP_ID" "SOURCE_SITE" "REASON" "CREATED_AT" "COMPLETE"
  printf '%s\n' "$(printf '=%.0s' {1..150})"

  if [[ -z "${entries//[[:space:]]/}" ]]; then
    return 0
  fi

  echo "${entries}" | jq -r '
    select(type == "object") |
    "\(.backup_id // "?" | (if length > 40 then .[0:37] + "..." else . end))  \(.source_site // "?" | (if length > 20 then .[0:17] + "..." else . end))  \(.reason // "?" | (if length > 30 then .[0:27] + "..." else . end))  \(.created_at // "?" | (if length > 15 then .[0:12] + "..." else . end))  \(.complete // "?")"
  '
}

bt_list_count() {
  local entries="$1"
  echo "${entries}" | jq -s 'length'
}

bt_list_get_display_name() {
  local backup_obj="$1"
  
  jq -r '.display_name // .reason // .backup_id' <<<"${backup_obj}"
}
