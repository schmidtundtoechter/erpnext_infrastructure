#!/usr/bin/env bash

declare -ag BT_TEMP_DIRS=()

bt_die() {
  local message="${1:-unexpected error}"
  printf 'ERROR: %s\n' "${message}" >&2
  exit 1
}

bt_require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || bt_die "Missing required command: ${cmd}"
}

bt_register_temp_dir() {
  local temp_dir="$1"
  BT_TEMP_DIRS+=("${temp_dir}")
}

bt_cleanup_temp_dirs() {
  local dir
  for dir in "${BT_TEMP_DIRS[@]:-}"; do
    [[ -n "${dir}" && -d "${dir}" ]] && rm -rf "${dir}"
  done
  BT_TEMP_DIRS=()
}

bt_make_temp_dir() {
  local prefix="${1:-backupctl}"
  local temp_dir
  temp_dir="$(mktemp -d -t "${prefix}.XXXXXX")"
  bt_register_temp_dir "${temp_dir}"
  printf '%s\n' "${temp_dir}"
}

bt_setup_cleanup_trap() {
  trap bt_cleanup_temp_dirs EXIT
}

bt_json_get() {
  local json_file="$1"
  local jq_filter="$2"
  bt_require_command jq
  jq -r "${jq_filter}" "${json_file}"
}

bt_json_set() {
  local json_file="$1"
  local jq_filter="$2"
  local temp_file

  bt_require_command jq
  temp_file="$(mktemp)"
  jq "${jq_filter}" "${json_file}" >"${temp_file}"
  mv "${temp_file}" "${json_file}"
}

bt_setup_cleanup_trap