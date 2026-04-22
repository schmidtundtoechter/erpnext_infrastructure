#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/config/nodes.json"

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  grep -Fq "${needle}" <<<"${haystack}" || fail "expected '${needle}' in '${haystack}'"
}

run_libs() {
  local snippet="$1"
  bash -c "set -euo pipefail; \
    source '${ROOT_DIR}/lib/common.sh'; \
    source '${ROOT_DIR}/lib/log.sh'; \
    source '${ROOT_DIR}/lib/config.sh'; \
    source '${ROOT_DIR}/lib/nodes.sh'; \
    ${snippet}"
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

test_config_example_exists_and_validates() {
  assert_file_exists "${CONFIG_PATH}"
  run_libs "bt_validate_config '${CONFIG_PATH}'"
}

test_config_model_fields_are_present() {
  run_libs "bt_load_config '${CONFIG_PATH}'; bt_get_node_json local-dev >/dev/null"
  run_libs "bt_load_config '${CONFIG_PATH}'; bt_get_node_json own-prod-01 >/dev/null"

  local source_kind
  source_kind="$(run_libs "bt_load_config '${CONFIG_PATH}'; bt_get_node_field local-dev source_kind")"
  [[ "${source_kind}" == "frappe-backup-dir" ]] || fail "unexpected source_kind: ${source_kind}"
}

test_runner_builds_commands_for_all_access_types() {
  local cmd_local cmd_local_docker cmd_ssh_host cmd_ssh_docker

  cmd_local="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node own-prod-01 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_local}" "ssh -o BatchMode=yes"
  assert_contains "${cmd_local}" "ops@own-prod-01.example.net"

  cmd_local_docker="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node local-dev 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_local_docker}" "docker exec -i"
  assert_contains "${cmd_local_docker}" "backend"

  cmd_ssh_host="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node archive-share 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_ssh_host}" "backup@archive.example.net"

  cmd_ssh_docker="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node customer-a-prod 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_ssh_docker}" "frappe@customer-a.example.net"
  assert_contains "${cmd_ssh_docker}" "docker\\ compose\\ exec\\ -T"
}

test_runner_reachability_dry_run_and_transfer_helper() {
  run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run bt_check_node_reachability customer-a-prod"

  local transfer_cmd
  transfer_cmd="$(run_libs "bt_load_config '${CONFIG_PATH}'; build_transfer_command archive-share own-prod-01 '/srv/customer-backups/a.tgz' '/home/frappe/incoming/a.tgz'")"
  assert_contains "${transfer_cmd}" "rsync -a --partial --progress"
  assert_contains "${transfer_cmd}" "backup@archive.example.net:/srv/customer-backups/a.tgz"
  assert_contains "${transfer_cmd}" "ops@own-prod-01.example.net:/home/frappe/incoming/a.tgz"
}

run_all_tests() {
  test_structure_files_exist
  test_shell_standard_is_set
  test_central_entrypoint_usage
  test_config_example_exists_and_validates
  test_config_model_fields_are_present
  test_runner_builds_commands_for_all_access_types
  test_runner_reachability_dry_run_and_transfer_helper
  printf 'PASS: all tests successful\n'
}

run_all_tests
