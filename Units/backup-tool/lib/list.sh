#!/usr/bin/env bash

list_usage() {
  cat <<'EOF'
Usage: backupctl backup list [options]

Shows backups from the LOCAL CACHE only. Does not connect to any node.
Run 'backupctl node scan' first to populate the cache.

Options:
  --format text|json        Output format (default: text)
  --node <id>               Filter by source node
  --site <site>             Filter by source site
  --tag <tag>               Filter by tag
  --reason-contains <text>  Filter by reason substring
  --complete true|false     Filter by completeness
  --from <iso8601>          Filter created_at >= from
  --to <iso8601>            Filter created_at <= to
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
  if ! bt_cache_has_node_files; then
    bt_log_info "Cache is empty. Run 'backupctl node scan' to populate it."
    case "${format}" in
      json) printf '[]\n' ;;
      *) printf '(no backups in cache)\n' ;;
    esac
    return 0
  fi

  local all_entries
  all_entries="$(bt_cache_list_all)"
  
  local filtered_entries
  filtered_entries="$(bt_cache_filter "${all_entries}" "${node_filter}" "${site_filter}" \
    "${tag_filter}" "${reason_filter}" "${complete_filter}" "${from_date}" "${to_date}")"

  local filtered_entries_json enriched_entries
  filtered_entries_json="$(printf '%s\n' "${filtered_entries}" | jq -s '.')"
  enriched_entries="$(bt_cache_entries_with_scan_state "${filtered_entries_json}")"
  
  case "${format}" in
    json)
      printf '%s\n' "${enriched_entries}" | jq .
      ;;
    text)
      bt_list_print_scan_overview "${node_filter}"
      printf '\n'
      bt_list_format_text "${enriched_entries}"
      ;;
    *)
      bt_die "Unknown list format: ${format}"
      ;;
  esac
}

bt_list_print_scan_overview() {
  local node_filter="${1:-}"
  local overview_rows

  overview_rows="$(bt_cache_scan_state_rows_json)"
  if [[ -n "${node_filter}" ]]; then
    overview_rows="$(jq -c --arg node "${node_filter}" 'map(select(.node == $node))' <<<"${overview_rows}")"
  fi

  printf 'Cache overview:\n'
  printf '%-25s %-10s %-10s %-20s %s\n' 'NODE' 'REACHABLE' 'BACKUPS' 'LAST_SCAN' 'CACHE'
  printf '%s\n' "$(printf '=%.0s' {1..86})"

  jq -r '.[] | [.node, .reachable, (.backups | tostring), .last_scan_at, .cache_status] | @tsv' <<<"${overview_rows}" \
    | awk -F'\t' '{ printf "%-25s %-10s %-10s %-20s %s\n", $1, $2, $3, $4, $5 }'
}

bt_list_format_text() {
  local entries="$1"
  
  printf '%-8s %-40s %-20s %-30s %-20s %-20s %s\n' "HASH" "BACKUP_ID" "SOURCE_SITE" "REASON" "CREATED_AT" "LAST_SCAN" "ART"
  printf '%s\n' "$(printf '=%.0s' {1..198})"

  if [[ -z "${entries//[[:space:]]/}" ]]; then
    return 0
  fi

  printf '%s\n' "${entries}" | jq -r -s '
    def normalize_input:
      if (length == 1 and (.[0] | type) == "array") then .[0] else . end;
    def artifact_code($a):
      ((if (($a.db_dump? // "") != "") then "D" else "" end)
      + (if (($a.site_config? // "") != "") then "S" else "" end)
      + (if (($a.public_files? // "") != "") then "F" else "" end)
      + (if (($a.private_files? // "") != "") then "P" else "" end)
      + (if (($a.manifest? // "") != "") then "M" else "" end)
      + (if (($a.checksums? // "") != "") then "C" else "" end)
      + (if (($a.apps? // "") != "") then "A" else "" end));
    normalize_input
    | map(select(type == "object"))[]
    | (.artifacts // {}) as $a
    | [
        (.backup_hash // "?" | tostring | .[0:8]),
        (.backup_id // "?" | tostring | if length > 40 then .[0:37] + "..." else . end),
        (.source_site // "?" | tostring | if length > 20 then .[0:17] + "..." else . end),
        (.reason // "?" | tostring | if length > 30 then .[0:27] + "..." else . end),
        (.created_at // "?" | tostring | if length > 20 then .[0:19] else . end),
        (.last_scan_at // "-" | tostring | if length > 20 then .[0:19] else . end),
        artifact_code($a)
      ]
    | @tsv
  ' | awk -F'\t' '{ printf "%-8s %-40s %-20s %-30s %-20s %-20s %s\n", $1, $2, $3, $4, $5, $6, $7 }'
}

bt_list_count() {
  local entries="$1"
  echo "${entries}" | jq -s 'length'
}

bt_list_get_display_name() {
  local backup_obj="$1"
  
  jq -r '.display_name // .reason // .backup_id' <<<"${backup_obj}"
}
