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
    def normalized_node:
      . as $node
      | $node
      | .node_type = (($node.node_type // $node.source_kind // empty) | normalize_node_type)
      | .access = (($node.access // $node.access_type // empty) | normalize_access)
      | .backup_path = ($node.backup_path // ($node.backup_paths[0] // empty));
    .nodes
    | all(.[];
      (normalized_node | (.id | type == "string" and length > 0)
      and ((.node_type == "frappe-node") or (.node_type == "plain-dir"))
      and ((.access == "local") or (.access == "docker") or (.access == "ssh") or (.access == "ssh-docker"))
      and (.backup_path | type == "string" and length > 0))
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: invalid required node fields"

  jq -e '
    def normalize_node_type:
      if . == "frappe-backup-dir" then "frappe-node"
      elif . == "plain-backup-dir" then "plain-dir"
      else .
      end;
    def normalized_node:
      . as $node
      | $node
      | .node_type = (($node.node_type // $node.source_kind // empty) | normalize_node_type);
    .nodes
    | all(.[];
      if (normalized_node | .node_type) == "frappe-node"
      then (.bench_path | type == "string" and length > 0)
      else true
      end
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: bench_path is required for node_type=frappe-node"

  jq -e '
    def normalize_access:
      if . == "local-docker" then "docker"
      elif . == "ssh-host" then "ssh"
      else .
      end;
    def normalized_node:
      . as $node
      | $node
      | .access = (($node.access // $node.access_type // empty) | normalize_access);
    .nodes
    | all(.[];
      if ((normalized_node | .access) == "ssh" or (normalized_node | .access) == "ssh-docker")
      then (.ssh_config | type == "string" and length > 0)
      else true
      end
    )
  ' "${config_path}" >/dev/null || bt_die "Config validation failed: ssh_config is required for ssh access"

  jq -e '
    def normalize_access:
      if . == "local-docker" then "docker"
      elif . == "ssh-host" then "ssh"
      else .
      end;
    def normalized_node:
      . as $node
      | $node
      | .access = (($node.access // $node.access_type // empty) | normalize_access);
    .nodes
    | all(.[];
      if ((normalized_node | .access) == "docker" or (normalized_node | .access) == "ssh-docker")
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
      and ((.ssh_config == null) or (.ssh_config | type == "string" and length > 0))
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
