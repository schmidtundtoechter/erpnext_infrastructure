#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

test_structure_files_exist() {
  assert_file_exists "${ROOT_DIR}/bin/backupctl"
  assert_file_exists "${ROOT_DIR}/lib/config.sh"
  assert_file_exists "${ROOT_DIR}/lib/nodes.sh"
  assert_file_exists "${ROOT_DIR}/lib/scan.sh"
  assert_file_exists "${ROOT_DIR}/lib/backup.sh"
  assert_file_exists "${ROOT_DIR}/lib/copy.sh"
  assert_file_exists "${ROOT_DIR}/lib/restore.sh"
  assert_file_exists "${ROOT_DIR}/lib/cache.sh"
  assert_file_exists "${ROOT_DIR}/lib/log.sh"
  assert_file_exists "${ROOT_DIR}/lib/common.sh"
}

test_shell_standard_is_set() {
  assert_file_contains "${ROOT_DIR}/bin/backupctl" "set -euo pipefail"
}

test_central_entrypoint_usage() {
  "${ROOT_DIR}/bin/backupctl" help >/dev/null
}

run_all_tests() {
  test_structure_files_exist
  test_shell_standard_is_set
  test_central_entrypoint_usage
  printf 'PASS: all tests successful\n'
}

run_all_tests