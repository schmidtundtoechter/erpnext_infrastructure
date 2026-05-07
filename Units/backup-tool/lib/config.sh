#!/usr/bin/env bash

BT_CONFIG_PATH=""

bt_seed_config_path() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "${root_dir}/config/nodes.json"
}

bt_normalize_node_json() {
  local node_json="$1"

  jq -c '
    def normalize_node_type:
      if . == "frappe-backup-dir" then "frappe-node"
      elif . == "plain-backup-dir" then "plain-dir"
      else .
      end;
    def normalize_access:
      if . == "local-docker" then "docker"
      elif . == "ssh-host" then "ssh"
      else .
      end;
    . as $node
    | $node
    | .node_type = (($node.node_type // $node.source_kind // empty) | normalize_node_type)
    | .access = (($node.access // $node.access_type // empty) | normalize_access)
    | .backup_path = ($node.backup_path // ($node.backup_paths[0] // empty))
    | del(.source_kind, .access_type, .backup_paths)
  ' <<<"${node_json}"
}

bt_default_config_path() {
  if [[ -n "${BACKUPCTL_CONFIG_PATH:-}" ]]; then
    printf '%s\n' "${BACKUPCTL_CONFIG_PATH}"
    return
  fi

  local default_config_path
  local seed_config_path

  default_config_path="${HOME}/.erpnext-nodes.json"
  seed_config_path="$(bt_seed_config_path)"

  if [[ ! -e "${default_config_path}" && ! -L "${default_config_path}" ]]; then
    [[ -f "${seed_config_path}" ]] || bt_die "Seed config not found: ${seed_config_path}"
    cp "${seed_config_path}" "${default_config_path}"
    bt_log_info "Initialized default config at ${default_config_path} from ${seed_config_path}"
  fi

  printf '%s\n' "${default_config_path}"
}

bt_validate_config() {
  local config_path="$1"

  [[ -f "${config_path}" ]] || bt_die "Config file not found: ${config_path}"
  bt_require_command jq

  jq -e . "${config_path}" >/dev/null || bt_die "Invalid JSON in config: ${config_path}"

  jq -e '.nodes | type == "array" and length > 0' "${config_path}" >/dev/null \
    || bt_die "Config must contain a non-empty nodes array"

  jq -e '
    def normalize_node_type:
      if . == "frappe-backup-dir" then "frappe-node"
      elif . == "plain-backup-dir" then "plain-dir"
      else .
      end;
    def normalize_access:
      if . == "local-docker" then "docker"
      elif . == "ssh-host" then "ssh"
      else .
      end;
    def n:
      . as $nd
      | $nd
      | .node_type  = (($nd.node_type  // $nd.source_kind  // empty) | normalize_node_type)
      | .access     = (($nd.access     // $nd.access_type  // empty) | normalize_access)
      | .backup_path = ($nd.backup_path // ($nd.backup_paths[0] // empty));
    .nodes | all(.[];
      (n | (.id | type == "string" and length > 0)
      and (.node_type | IN("frappe-node","plain-dir"))
      and (.access    | IN("local","docker","ssh","ssh-docker"))
      and (.backup_path | type == "string" and length > 0)
      and (if .node_type == "frappe-node"
           then (.bench_path | type == "string" and length > 0) else true end)
      and (if (.access | IN("ssh","ssh-docker"))
           then (.ssh_config | type == "string" and length > 0) else true end)
      and (if (.access | IN("docker","ssh-docker"))
           then ((.container | type == "string" and length > 0)
              or (.compose_service | type == "string" and length > 0)) else true end))
      and ((.tags           == null) or (.tags           | type == "array" and all(.[]; type == "string")))
      and ((.vpn_required   == null) or (.vpn_required   | type == "boolean"))
      and ((.description    == null) or (.description    | type == "string"))
      and ((.enabled        == null) or (.enabled        | type == "boolean"))
      and ((.ssh_config     == null) or (.ssh_config     | type == "string" and length > 0))
      and ((.container      == null) or (.container      | type == "string" and length > 0))
      and ((.compose_service == null) or (.compose_service | type == "string" and length > 0))
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: invalid node configuration"
}

bt_load_config() {
  local config_path="${1:-$(bt_default_config_path)}"
  bt_validate_config "${config_path}"
  BT_CONFIG_PATH="${config_path}"
  bt_log_info "Loaded config from ${config_path}"
}

bt_require_loaded_config() {
  [[ -n "${BT_CONFIG_PATH}" ]] || bt_load_config
}

bt_list_node_ids() {
  bt_require_loaded_config
  jq -r '.nodes[].id' "${BT_CONFIG_PATH}"
}

bt_get_node_json() {
  local node_id="$1"
  local node_json

  bt_require_loaded_config

  node_json="$(jq -cer --arg id "${node_id}" '.nodes[] | select(.id == $id)' "${BT_CONFIG_PATH}")" \
    || bt_die "Unknown node id: ${node_id}"

  bt_normalize_node_json "${node_json}"
}

bt_get_node_field() {
  local node_id="$1"
  local field="$2"

  case "${field}" in
    source_kind)
      field="node_type"
      ;;
    access_type)
      field="access"
      ;;
  esac

  bt_get_node_json "${node_id}" | jq -r --arg field "${field}" '.[$field] // empty'
}

nodes_list() {
  bt_print_node_overview_table "Node overview"
}

bt_node_overview_rows_json() {
  local node_filter="${1:-}"
  local node_rows scan_states live_counts nid count

  bt_require_loaded_config

  node_rows="$(jq -c '
    def normalize_node_type:
      if . == "frappe-backup-dir" then "frappe-node"
      elif . == "plain-backup-dir" then "plain-dir"
      else .
      end;
    def normalize_access:
      if . == "local-docker" then "docker"
      elif . == "ssh-host" then "ssh"
      else .
      end;
    def host_value:
      (.ssh_config // .host // "-");
    [
      .nodes[]
      | {
          node: (.id | tostring),
          host: (host_value | tostring),
          node_type: ((.node_type // .source_kind // "?") | normalize_node_type | tostring),
          access: ((.access // .access_type // "?") | normalize_access | tostring),
          enabled: ((.enabled // true) | tostring)
        }
    ]
  ' "${BT_CONFIG_PATH}")"

  scan_states="$(bt_cache_scan_state_all)"

  live_counts="$(
    while IFS= read -r nid; do
      count="$(bt_cache_node_backup_count "${nid}")"
      jq -cn --arg nid "${nid}" --argjson count "${count}" '{($nid): $count}'
    done < <(bt_list_node_ids) | jq -sc 'add // {}'
  )"

  jq -cn \
    --argjson nodes "${node_rows}" \
    --argjson states "${scan_states}" \
    --argjson counts "${live_counts}" \
    --arg filter "${node_filter}" '
    $states as $scan_map
    | $counts as $count_map
    | $nodes
    | (if ($filter | length) > 0 then map(select(.node == $filter)) else . end)
    | map(
        . as $node
        | ($scan_map[$node.node] // {}) as $state
        | $node
        + {
            reachable: ($state.reachable // "unknown"),
            backups: (($count_map[$node.node] // 0) | tostring),
            last_scan_at: ($state.last_scan_at // "-"),
            cache_status: ($state.cache_status // "not-scanned")
          }
      )
  '
}

bt_print_node_overview_table() {
  local title="${1:-Node overview}"
  local node_filter="${2:-}"
  local overview_rows

  overview_rows="$(bt_node_overview_rows_json "${node_filter}")"

  printf '%s:\n' "${title}"

  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      'NODE' 'HOST' 'TYPE' 'ACCESS' 'EN' 'UP' 'BKP' 'LAST_SCAN' 'CACHE'
    jq -r '
      .[]
      | [
          (.node | tostring),
          (.host | tostring),
          (.node_type | tostring),
          (.access | tostring),
          (if ((.enabled | tostring) | test("^(true|yes|1)$"; "i")) then "Y" else "N" end),
          (if ((.reachable | tostring) | test("^(yes|true|1)$"; "i")) then "Y" else "N" end),
          (.backups | tostring),
          (.last_scan_at // "-" | tostring | if length > 10 then .[0:10] else . end),
          (.cache_status | tostring)
        ]
      | @tsv
    ' <<<"${overview_rows}"
  } | awk -F'\t' '
    {
      rows[NR] = $0
      n = split($0, f, FS)
      for (i = 1; i <= n; i++)
        if (length(f[i]) > w[i]) w[i] = length(f[i])
      if (n > ncols) ncols = n
    }
    END {
      sep_len = 0
      for (i = 1; i <= ncols; i++) sep_len += w[i] + (i < ncols ? 2 : 0)
      for (r = 1; r <= NR; r++) {
        n = split(rows[r], f, FS)
        for (i = 1; i <= ncols; i++) {
          v = (i <= n ? f[i] : "")
          if (i < ncols) printf "%-*s  ", w[i], v
          else printf "%s", v
        }
        printf "\n"
        if (r == 1) {
          for (j = 0; j < sep_len; j++) printf "="
          printf "\n"
        }
      }
    }
  '
}
