#!/usr/bin/env bash

BT_CONFIG_PATH=""

bt_seed_config_path() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "${root_dir}/config/nodes.json"
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
    .nodes
    | all(.[];
      (.id | type == "string" and length > 0)
      and ((.source_kind == "frappe-backup-dir") or (.source_kind == "plain-backup-dir"))
      and ((.access_type == "local") or (.access_type == "local-docker") or (.access_type == "ssh-host") or (.access_type == "ssh-docker"))
      and (.backup_paths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: invalid required node fields"

  jq -e '
    .nodes
    | all(.[];
      if .source_kind == "frappe-backup-dir"
      then (.bench_path | type == "string" and length > 0)
      else true
      end
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: bench_path is required for source_kind=frappe-backup-dir"

  jq -e '
    .nodes
    | all(.[];
      if (.access_type == "ssh-host" or .access_type == "ssh-docker")
      then ((.host | type == "string" and length > 0) and (.user | type == "string" and length > 0) and ((.port == null) or ((.port | type) == "number" and .port >= 1 and .port <= 65535)))
      else true
      end
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: host/user are required for ssh access and port must be 1..65535 when set"

  jq -e '
    .nodes
    | all(.[];
      if (.access_type == "local-docker" or .access_type == "ssh-docker")
      then ((.container | type == "string" and length > 0) or (.compose_service | type == "string" and length > 0))
      else true
      end
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: docker access requires container or compose_service"

  jq -e '
    .nodes
    | all(.[];
      ((.tags == null) or (.tags | type == "array" and all(.[]; type == "string")))
      and ((.vpn_required == null) or ((.vpn_required | type) == "boolean"))
      and ((.description == null) or (.description | type == "string"))
      and ((.enabled == null) or ((.enabled | type) == "boolean"))
      and ((.container == null) or (.container | type == "string" and length > 0))
      and ((.compose_service == null) or (.compose_service | type == "string" and length > 0))
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: optional fields have invalid types"
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

  bt_require_loaded_config

  jq -cer --arg id "${node_id}" '.nodes[] | select(.id == $id)' "${BT_CONFIG_PATH}" \
    || bt_die "Unknown node id: ${node_id}"
}

bt_get_node_field() {
  local node_id="$1"
  local field="$2"

  bt_get_node_json "${node_id}" | jq -r --arg field "${field}" '.[$field] // empty'
}
