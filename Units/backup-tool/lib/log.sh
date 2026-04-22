#!/usr/bin/env bash

bt_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

bt_log_info() {
  local message="$1"
  printf '%s [INFO] %s\n' "$(bt_timestamp)" "${message}" >&2
}

bt_log_warn() {
  local message="$1"
  printf '%s [WARN] %s\n' "$(bt_timestamp)" "${message}" >&2
}

bt_log_error() {
  local message="$1"
  printf '%s [ERROR] %s\n' "$(bt_timestamp)" "${message}" >&2
}