#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/config/nodes.test.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || {
        printf 'FAIL: --config requires a value\n' >&2
        exit 1
      }
      CONFIG_PATH="$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--config <path>]

Options:
  --config <path>   Pfad zur Test-Konfigurationsdatei (Default: config/nodes.test.json)
EOF
      exit 0
      ;;
    *)
      printf 'FAIL: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

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
    source '${ROOT_DIR}/lib/backup-model.sh'; \
    source '${ROOT_DIR}/lib/scan.sh'; \
    source '${ROOT_DIR}/lib/backup.sh'; \
    source '${ROOT_DIR}/lib/copy.sh'; \
    source '${ROOT_DIR}/lib/restore.sh'; \
    source '${ROOT_DIR}/lib/cache.sh'; \
    source '${ROOT_DIR}/lib/list.sh'; \
    ${snippet}"
}

test_structure_files_exist() {
  assert_file_exists "${ROOT_DIR}/bin/backupctl"
  assert_file_exists "${ROOT_DIR}/lib/config.sh"
  assert_file_exists "${ROOT_DIR}/lib/nodes.sh"
  assert_file_exists "${ROOT_DIR}/lib/backup-model.sh"
  assert_file_exists "${ROOT_DIR}/lib/scan.sh"
  assert_file_exists "${ROOT_DIR}/lib/backup.sh"
  assert_file_exists "${ROOT_DIR}/lib/copy.sh"
  assert_file_exists "${ROOT_DIR}/lib/restore.sh"
  assert_file_exists "${ROOT_DIR}/lib/cache.sh"
  assert_file_exists "${ROOT_DIR}/lib/list.sh"
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
  assert_contains "${cmd_local_docker}" "docker --context"
  assert_contains "${cmd_local_docker}" "exec -i"

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

test_backup_model_definition_exists() {
  local model_text
  model_text="$(run_libs "bt_backup_model_definition")"
  assert_contains "${model_text}" "backup_id"
  assert_contains "${model_text}" "source_node"
  assert_contains "${model_text}" "source_kind"
  assert_contains "${model_text}" "source_site"
  assert_contains "${model_text}" "created_at"
  assert_contains "${model_text}" "reason"
  assert_contains "${model_text}" "artifacts"
  assert_contains "${model_text}" "complete"
}

test_backup_id_generation() {
  local backup_id
  backup_id="$(run_libs "bt_generate_backup_id 'test-node' 'test.example.com'")"
  assert_contains "${backup_id}" "test-node"
  assert_contains "${backup_id}" "test.example.com"
}

test_manifest_json_generation() {
  local artifacts_json manifest_json backup_id
  
  artifacts_json='{"db_dump":"test-database.sql.gz","site_config":"site_config.json"}'
  manifest_json="$(run_libs "bt_generate_manifest_json 'backup_1234567890' 'test-node' 'test.site' 'Test backup reason' '${artifacts_json}' '[]' | jq -c .")"
  
  assert_contains "${manifest_json}" "backup_1234567890"
  assert_contains "${manifest_json}" "test-node"
  assert_contains "${manifest_json}" "test.site"
  assert_contains "${manifest_json}" "Test backup reason"
  assert_contains "${manifest_json}" "full-with-files"
  assert_contains "${manifest_json}" "true"
}

test_backup_is_complete_check() {
  local backup_complete backup_incomplete
  
  backup_complete='{"backup_id":"test","complete":true,"artifacts":{"db_dump":"db.gz","site_config":"config.json"}}'
  backup_incomplete='{"backup_id":"test","complete":false,"artifacts":{"db_dump":"db.gz"}}'
  
  run_libs "bt_backup_is_complete '${backup_complete}'" >/dev/null || fail "Complete backup should validate"
  
  if run_libs "bt_backup_is_complete '${backup_incomplete}'" >/dev/null 2>&1; then
    fail "Incomplete backup should not validate"
  fi
}

test_backup_display_name() {
  local backup_obj display_name
  
  backup_obj='{"backup_id":"test","reason":"Daily backup","display_name":"Custom name"}'
  display_name="$(run_libs "bt_backup_display_name '${backup_obj}'")"
  [[ "${display_name}" == "Custom name" ]] || fail "Should use display_name when present: ${display_name}"
  
  backup_obj='{"backup_id":"test","reason":"Daily backup"}'
  display_name="$(run_libs "bt_backup_display_name '${backup_obj}'")"
  [[ "${display_name}" == "Daily backup" ]] || fail "Should fallback to reason: ${display_name}"
}

test_backup_model_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/backup-model.sh"
  assert_file_contains "${ROOT_DIR}/lib/backup-model.sh" "bt_backup_model_definition"
  assert_file_contains "${ROOT_DIR}/lib/backup-model.sh" "bt_generate_backup_id"
  assert_file_contains "${ROOT_DIR}/lib/backup-model.sh" "bt_generate_manifest_json"
  assert_file_contains "${ROOT_DIR}/lib/backup-model.sh" "bt_validate_manifest_json"
}

test_cache_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/cache.sh"
  assert_file_contains "${ROOT_DIR}/lib/cache.sh" "bt_cache_init"
  assert_file_contains "${ROOT_DIR}/lib/cache.sh" "bt_cache_add_entry"
  assert_file_contains "${ROOT_DIR}/lib/cache.sh" "bt_cache_filter"
  assert_file_contains "${ROOT_DIR}/lib/cache.sh" "bt_cache_rebuild"
}

test_cache_entry_schema_exists() {
  local schema_text
  schema_text="$(run_libs "bt_cache_entry_schema")"
  assert_contains "${schema_text}" "backup_id"
  assert_contains "${schema_text}" "source_node"
  assert_contains "${schema_text}" "complete"
  assert_contains "${schema_text}" "last_seen"
}

test_backup_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/backup.sh"
  assert_file_contains "${ROOT_DIR}/lib/backup.sh" "backup_create_main"
  assert_file_contains "${ROOT_DIR}/lib/backup.sh" "create_backup_on_node"
}

test_list_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/list.sh"
  assert_file_contains "${ROOT_DIR}/lib/list.sh" "list_main"
  assert_file_contains "${ROOT_DIR}/lib/list.sh" "bt_list_format_text"
  assert_file_contains "${ROOT_DIR}/lib/list.sh" "bt_list_get_display_name"
}

test_copy_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/copy.sh"
  assert_file_contains "${ROOT_DIR}/lib/copy.sh" "backup_copy_main"
  assert_file_contains "${ROOT_DIR}/lib/copy.sh" "copy_backup_between_nodes"
  assert_file_contains "${ROOT_DIR}/lib/copy.sh" "build_transfer_command"
  assert_file_contains "${ROOT_DIR}/lib/copy.sh" "bt_validate_backup_transfer"
}

test_restore_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/restore.sh"
  assert_file_contains "${ROOT_DIR}/lib/restore.sh" "backup_restore_main"
  assert_file_contains "${ROOT_DIR}/lib/restore.sh" "restore_backup_to_node"
  assert_file_contains "${ROOT_DIR}/lib/restore.sh" "bt_handle_site_config_merge"
  assert_file_contains "${ROOT_DIR}/lib/restore.sh" "bt_execute_post_restore_tasks"
}

test_copy_requires_parameters() {
  # Should die when --backup is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --from local-dev --to own-prod-01" >/dev/null 2>&1; then
    fail "copy should require --backup parameter"
  fi
  
  # Should die when --from is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --backup test --to own-prod-01" >/dev/null 2>&1; then
    fail "copy should require --from parameter"
  fi
  
  # Should die when --to is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --backup test --from local-dev" >/dev/null 2>&1; then
    fail "copy should require --to parameter"
  fi
}

test_restore_requires_parameters() {
  # Should die when --backup is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_restore_main --to local-dev --site test.example.com" >/dev/null 2>&1; then
    fail "restore should require --backup parameter"
  fi
  
  # Should die when --to is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_restore_main --backup test --site test.example.com" >/dev/null 2>&1; then
    fail "restore should require --to parameter"
  fi
  
  # Should die when --site is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_restore_main --backup test --to local-dev" >/dev/null 2>&1; then
    fail "restore should require --site parameter"
  fi
}

test_restore_config_mode_validation() {
  # Should die on invalid config-mode
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_restore_main --backup test --to local-dev --site test --config-mode invalid-mode" >/dev/null 2>&1; then
    fail "restore should validate config-mode values"
  fi
}

test_global_dry_run_scan() {
  local out
  out="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run scan --node local-dev 2>&1)"
  assert_contains "${out}" "Would scan:"
}

test_global_dry_run_restore() {
  local out
  out="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run restore --backup demo_1 --to local-dev --site demo.local 2>&1)"
  assert_contains "${out}" "DRY-RUN: Would restore"
}

run_all_tests() {
  test_structure_files_exist
  test_shell_standard_is_set
  test_central_entrypoint_usage
  test_config_example_exists_and_validates
  test_config_model_fields_are_present
  test_runner_builds_commands_for_all_access_types
  test_runner_reachability_dry_run_and_transfer_helper
  test_backup_model_library_exists
  test_backup_model_definition_exists
  test_backup_id_generation
  test_manifest_json_generation
  test_backup_is_complete_check
  test_backup_display_name
  test_cache_library_exists
  test_cache_entry_schema_exists
  test_backup_library_exists
  test_list_library_exists
  test_copy_library_exists
  test_restore_library_exists
  test_copy_requires_parameters
  test_restore_requires_parameters
  test_restore_config_mode_validation
  test_global_dry_run_scan
  test_global_dry_run_restore
  printf 'PASS: all tests successful\n'
}

run_all_tests
