#!/usr/bin/env bash

bt_default_config_path() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "${root_dir}/config/nodes.json"
}

bt_load_config() {
  local config_path="${1:-$(bt_default_config_path)}"
  if [[ ! -f "${config_path}" ]]; then
    bt_die "Config file not found: ${config_path}"
  fi
  bt_log_info "Loaded config from ${config_path}"
}