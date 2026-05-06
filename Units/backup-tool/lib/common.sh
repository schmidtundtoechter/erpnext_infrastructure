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

bt_confirm_or_force() {
  local force_flag="$1"
  local prompt_message="$2"
  local answer

  if [[ -n "${force_flag}" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    bt_die "${prompt_message} Use -f or --force to proceed in non-interactive mode."
  fi

  printf '%s [y/N]: ' "${prompt_message}" >&2
  read -r answer

  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      bt_die "Operation aborted by user"
      ;;
  esac
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