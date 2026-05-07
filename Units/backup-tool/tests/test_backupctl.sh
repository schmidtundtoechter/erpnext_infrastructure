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
    source '${ROOT_DIR}/lib/remove.sh'; \
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
  assert_file_exists "${ROOT_DIR}/lib/remove.sh"
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

  local node_type
  node_type="$(run_libs "bt_load_config '${CONFIG_PATH}'; bt_get_node_field local-dev node_type")"
  [[ "${node_type}" == "frappe-node" ]] || fail "unexpected node_type: ${node_type}"

  local backup_path has_backup_paths
  backup_path="$(run_libs "bt_load_config '${CONFIG_PATH}'; bt_get_node_field local-dev backup_path")"
  [[ "${backup_path}" == "/Users/matthias/projects/frappe-bench/sites" ]] || fail "unexpected backup_path: ${backup_path}"
  has_backup_paths="$(jq '[.nodes[] | has("backup_paths")] | any' "${CONFIG_PATH}")"
  [[ "${has_backup_paths}" == "false" ]] || fail "config should use backup_path, not backup_paths"
}

test_runner_builds_commands_for_all_access_types() {
  local cmd_local cmd_local_docker cmd_ssh_host cmd_ssh_docker

  cmd_local="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node own-prod-01 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_local}" "ssh -n -o BatchMode=yes"
  assert_contains "${cmd_local}" "own-prod-01"

  cmd_local_docker="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node local-dev 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_local_docker}" "docker --context"
  assert_contains "${cmd_local_docker}" "exec -i"

  cmd_ssh_host="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node archive-share 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_ssh_host}" "archive-share"

  cmd_ssh_docker="$(run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run run_on_node customer-a-prod 'echo ok'" 2>/dev/null)"
  assert_contains "${cmd_ssh_docker}" "customer-a-prod"
  assert_contains "${cmd_ssh_docker}" "docker\\ compose\\ exec\\ -T"
}

test_runner_reachability_dry_run_and_transfer_helper() {
  run_libs "bt_load_config '${CONFIG_PATH}'; BT_RUNNER_MODE=dry-run bt_check_node_reachability customer-a-prod"

  local transfer_cmd
  transfer_cmd="$(run_libs "bt_load_config '${CONFIG_PATH}'; build_transfer_command archive-share own-prod-01 '/srv/customer-backups/a.tgz' '/home/frappe/incoming/a.tgz'")"
  assert_contains "${transfer_cmd}" "rsync -a --partial --progress"
  assert_contains "${transfer_cmd}" "archive-share:/srv/customer-backups/a.tgz"
  assert_contains "${transfer_cmd}" "own-prod-01:/home/frappe/incoming/a.tgz"
}

test_backup_model_definition_exists() {
  local model_text
  model_text="$(run_libs "bt_backup_model_definition")"
  assert_contains "${model_text}" "backup_id"
  assert_contains "${model_text}" "source_node"
  assert_contains "${model_text}" "node_type"
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
  assert_contains "${manifest_json}" "backup_hash"
  assert_contains "${manifest_json}" "true"
  assert_contains "${manifest_json}" "\"apps\":[]"
}

test_manifest_json_generation_with_apps() {
  local artifacts_json apps_json manifest_json

  artifacts_json='{"db_dump":"test-database.sql.gz","site_config":"site_config.json"}'
  apps_json='[{"app":"frappe","version":"15.68.0","branch":"version-15"},{"app":"erpnext","version":"15.63.1","branch":"version-15"}]'
  manifest_json="$(run_libs "bt_generate_manifest_json 'backup_apps_1' 'test-node' 'test.site' 'Test backup reason' '${artifacts_json}' '[]' '' '${apps_json}' | jq -c .")"

  assert_contains "${manifest_json}" "\"apps\":["
  assert_contains "${manifest_json}" "\"app\":\"frappe\""
  assert_contains "${manifest_json}" "\"version\":\"15.68.0\""
  assert_contains "${manifest_json}" "\"branch\":\"version-15\""
}

test_backup_hash_generation() {
  local hash
  hash="$(run_libs "bt_backup_hash_from_id 'backup_1234567890'")"
  [[ "${#hash}" -eq 6 ]] || fail "backup hash should be 6 chars: ${hash}"
}

test_backup_hash_uses_location() {
  local out

  out="$(run_libs "a='{\"backup_id\":\"demo_same\",\"source_node\":\"local-dev\",\"backup_path\":\"/sites\",\"source_rel_dir\":\"demo.local/private/backups\"}'; b='{\"backup_id\":\"demo_same\",\"source_node\":\"own-prod-01\",\"backup_path\":\"/sites\",\"source_rel_dir\":\"demo.local/private/backups\"}'; printf 'A=%s\n' \"\$(bt_backup_hash_from_object \"\${a}\")\"; printf 'B=%s\n' \"\$(bt_backup_hash_from_object \"\${b}\")\"")"

  local hash_a hash_b
  hash_a="$(awk -F= '/^A=/{print $2}' <<<"${out}")"
  hash_b="$(awk -F= '/^B=/{print $2}' <<<"${out}")"
  [[ "${#hash_a}" -eq 6 ]] || fail "location hash A should be 6 chars: ${hash_a}"
  [[ "${#hash_b}" -eq 6 ]] || fail "location hash B should be 6 chars: ${hash_b}"
  [[ "${hash_a}" != "${hash_b}" ]] || fail "location hashes should differ for different nodes"
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
  assert_file_contains "${ROOT_DIR}/lib/cache.sh" "bt_cache_upsert_entry"
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

test_cache_uses_per_node_files_and_aggregates_centrally() {
  local tmp_cache_dir out

  tmp_cache_dir="$(mktemp -d)"
  out="$(run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_1\",\"source_node\":\"local-dev\",\"source_site\":\"site-a\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_2\",\"source_node\":\"archive-share\",\"source_site\":\"site-b\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"b.sql.gz\",\"site_config\":\"site_config.json\"}}'; printf 'FILES=%s\n' \"\$(find '${tmp_cache_dir}/nodes' -type f -name '*.json' | wc -l | tr -d ' ')\"; printf 'COUNT=%s\n' \"\$(bt_cache_list_all | jq 'length')\"")"

  assert_contains "${out}" "FILES=2"
  assert_contains "${out}" "COUNT=2"
}

test_cache_prunes_removed_node_files() {
  local tmp_cache_dir

  tmp_cache_dir="$(mktemp -d)"
  mkdir -p "${tmp_cache_dir}/nodes"
  printf '[]\n' > "${tmp_cache_dir}/nodes/obsolete-node.json"

  run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_list_all >/dev/null; [[ ! -e '${tmp_cache_dir}/nodes/obsolete-node.json' ]]" \
    || fail "expected obsolete node cache file to be pruned"
}

test_backup_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/backup.sh"
  assert_file_contains "${ROOT_DIR}/lib/backup.sh" "backup_create_main"
  assert_file_contains "${ROOT_DIR}/lib/backup.sh" "create_backup_on_node"
}

test_backup_create_can_infer_single_site_from_cache_and_default_reason() {
  local tmp_cache_dir out

  tmp_cache_dir="$(mktemp -d)"
  out="$(run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_existing\",\"source_node\":\"local-dev\",\"source_site\":\"demo.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; BT_RUNNER_MODE=dry-run backup_create_main --node local-dev 2>&1")"

  assert_contains "${out}" "Creating backup: node=local-dev site=demo.local reason=manual backup create"
  assert_contains "${out}" "Would create backup on local-dev for site demo.local"
}

test_backup_create_requires_site_when_multiple_sites_are_known() {
  local tmp_cache_dir

  tmp_cache_dir="$(mktemp -d)"
  if run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_a\",\"source_node\":\"local-dev\",\"source_site\":\"a.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_b\",\"source_node\":\"local-dev\",\"source_site\":\"b.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"b.sql.gz\",\"site_config\":\"site_config.json\"}}'; BT_RUNNER_MODE=dry-run backup_create_main --node local-dev >/dev/null 2>&1"; then
    fail "backup create should require --site when multiple sites are known"
  fi
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

test_remove_library_exists() {
  assert_file_exists "${ROOT_DIR}/lib/remove.sh"
  assert_file_contains "${ROOT_DIR}/lib/remove.sh" "backup_remove_main"
  assert_file_contains "${ROOT_DIR}/lib/remove.sh" "remove_backup_by_id"
}

test_copy_requires_parameters() {
  # Should die when --backup is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --to own-prod-01" >/dev/null 2>&1; then
    fail "copy should require --backup parameter"
  fi
  
  # Should die when --to is missing
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --backup test" >/dev/null 2>&1; then
    fail "copy should require --to parameter"
  fi
}

test_copy_can_infer_from_node_from_cache() {
  local tmp_cache_dir out

  tmp_cache_dir="$(mktemp -d)"
  out="$(run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_copy_1\",\"source_node\":\"local-dev\",\"source_site\":\"demo.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; BT_RUNNER_MODE=dry-run backup_copy_main --backup demo_copy_1 --to own-prod-01 2>&1")"

  assert_contains "${out}" "Resolved source node from cache: local-dev"
  assert_contains "${out}" "Would copy backup demo_copy_1 from local-dev to own-prod-01"
}

test_copy_uses_cached_location_for_source_and_target_paths() {
  local out

  out="$(run_libs "bt_load_config '${CONFIG_PATH}'; entry='{\"backup_id\":\"demo_copy_2\",\"source_node\":\"local-dev\",\"node_type\":\"frappe-node\",\"source_site\":\"demo.local\",\"backup_path\":\"/Users/matthias/projects/frappe-bench/sites\",\"source_rel_dir\":\"demo.local/private/backups\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; printf 'SRC=%s\n' \"\$(bt_get_backup_path_for_node local-dev demo_copy_2 \"\${entry}\")\"; printf 'DST=%s\n' \"\$(bt_get_target_backup_path_for_node own-prod-01 demo_copy_2 \"\${entry}\")\"")"

  assert_contains "${out}" "SRC=/Users/matthias/projects/frappe-bench/sites/demo.local/private/backups"
  assert_contains "${out}" "DST=/home/frappe/frappe-bench/sites/demo.local/private/backups"
}

test_copy_cache_entry_gets_new_hash_and_origin_hash() {
  local out

  out="$(run_libs "bt_load_config '${CONFIG_PATH}'; src='{\"backup_id\":\"demo_copy_3\",\"backup_hash\":\"abc123\",\"source_node\":\"local-dev\",\"node_type\":\"frappe-node\",\"source_site\":\"demo.local\",\"backup_path\":\"/Users/matthias/projects/frappe-bench/sites\",\"source_rel_dir\":\"demo.local/private/backups\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\",\"site_config\":\"site_config.json\"}}'; bt_get_cached_backup_object own-prod-01 demo_copy_3 \"\${src}\" | jq -r '[.backup_id,.backup_hash,.origin_backup_hash,.copied_from_node,.source_node,.backup_path] | @tsv'")"

  assert_contains "${out}" "demo_copy_3"
  assert_contains "${out}" "abc123"
  assert_contains "${out}" "local-dev"
  assert_contains "${out}" "own-prod-01"
  assert_contains "${out}" "/home/frappe/frappe-bench/sites"
  if awk -F'\t' '{ exit !($2 == "abc123") }' <<<"${out}"; then
    fail "copied backup hash should differ from origin hash"
  fi
}

test_scan_local_frappe_records_backup_path_and_relative_dir() {
  local tmp_dir config_path out

  tmp_dir="$(mktemp -d)"
  mkdir -p "${tmp_dir}/sites/demo.local/private/backups" "${tmp_dir}/sites/demo.local"
  touch "${tmp_dir}/sites/demo.local/private/backups/20260507_001200-demo.local-database.sql.gz"
  touch "${tmp_dir}/sites/demo.local/private/backups/20260507_001200-demo.local-files.tar"
  touch "${tmp_dir}/sites/demo.local/private/backups/20260507_001200-demo.local-private-files.tar"
  touch "${tmp_dir}/sites/demo.local/site_config.json"
  config_path="${tmp_dir}/nodes.json"
  jq -n --arg bp "${tmp_dir}/sites" '{nodes:[{id:"tmp-local",node_type:"frappe-node",access:"local",bench_path:"/tmp/bench",backup_path:$bp,enabled:true}]}' > "${config_path}"

  out="$(run_libs "bt_load_config '${config_path}'; scan_node tmp-local | jq -c '{backup_path, source_rel_dir, source_site, artifacts}'")"

  assert_contains "${out}" "\"backup_path\":\"${tmp_dir}/sites\""
  assert_contains "${out}" "\"source_rel_dir\":\"demo.local/private/backups\""
  assert_contains "${out}" "\"source_site\":\"demo.local\""
  assert_contains "${out}" "\"public_files\":\"20260507_001200-demo.local-files.tar\""
  assert_contains "${out}" "\"private_files\":\"20260507_001200-demo.local-private-files.tar\""
  [[ ! -e "${tmp_dir}/sites/demo.local/private/backups/manifest.json" ]] || fail "scan should not create a manifest for manifestless backups"
}

test_scan_updates_existing_manifest_hash() {
  local tmp_dir config_path out manifest_hash output_hash

  tmp_dir="$(mktemp -d)"
  mkdir -p "${tmp_dir}/sites/demo.local/private/backups" "${tmp_dir}/sites/demo.local"
  touch "${tmp_dir}/sites/demo.local/private/backups/20260507_001200-demo.local-database.sql.gz"
  jq -n '{
    backup_id: "demo_backup_1",
    backup_hash: "old123",
    created_at: "2026-05-07T00:12:00Z",
    source_node: "old-node",
    source_site: "demo.local",
    backup_type: "full-with-files",
    reason: "test manifest",
    artifacts: {db_dump: "20260507_001200-demo.local-database.sql.gz"},
    complete: true
  }' > "${tmp_dir}/sites/demo.local/private/backups/manifest.json"
  config_path="${tmp_dir}/nodes.json"
  jq -n --arg bp "${tmp_dir}/sites" '{nodes:[{id:"tmp-local",node_type:"frappe-node",access:"local",bench_path:"/tmp/bench",backup_path:$bp,enabled:true}]}' > "${config_path}"

  out="$(run_libs "bt_load_config '${config_path}'; scan_node tmp-local")"
  output_hash="$(jq -r '.backup_hash' <<<"${out}")"
  manifest_hash="$(jq -r '.backup_hash' "${tmp_dir}/sites/demo.local/private/backups/manifest.json")"

  [[ "${output_hash}" != "old123" ]] || fail "scan output hash should be recalculated"
  [[ "${manifest_hash}" == "${output_hash}" ]] || fail "manifest hash should be updated to scan hash"
}

test_list_text_shows_node_instead_of_source_site() {
  local out

  out="$(run_libs "entry='[{\"backup_id\":\"demo_list_1\",\"backup_hash\":\"abc123\",\"source_node\":\"local-dev\",\"source_site\":\"demo.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"last_scan_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a.sql.gz\"}}]'; bt_list_format_text \"\${entry}\"")"

  assert_contains "${out}" "HASH"
  assert_contains "${out}" "NODE"
  assert_contains "${out}" "LAST_SCAN"
  assert_contains "${out}" "local-dev"
  if grep -Fq "SOURCE_SITE" <<<"${out}"; then
    fail "list header should not contain SOURCE_SITE"
  fi
}

test_copy_rejects_removed_from_option() {
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_copy_main --backup demo_copy_1 --from local-dev --to own-prod-01" >/dev/null 2>&1; then
    fail "copy should reject removed --from option"
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

test_restore_app_compatibility_check_passes_on_matching_apps() {
  run_libs '
    run_on_node() { return 0; }
    bt_collect_site_apps_json() { printf "[%s]\n" "{\"app\":\"frappe\",\"version\":\"15.68.0\",\"branch\":\"version-15\"}"; }
    entry="{\"apps\":[{\"app\":\"frappe\",\"version\":\"15.68.0\",\"branch\":\"version-15\"}]}"
    bt_restore_check_app_compatibility "${entry}" local-dev demo.local /tmp/bench
  ' >/dev/null || fail "restore app compatibility should pass on matching apps"
}

test_restore_app_compatibility_check_fails_on_mismatch() {
  if run_libs '
    run_on_node() { return 0; }
    bt_collect_site_apps_json() { printf "[%s]\n" "{\"app\":\"frappe\",\"version\":\"15.68.0\",\"branch\":\"version-15\"}"; }
    entry="{\"apps\":[{\"app\":\"frappe\",\"version\":\"15.67.0\",\"branch\":\"version-15\"}]}"
    bt_restore_check_app_compatibility "${entry}" local-dev demo.local /tmp/bench
  ' >/dev/null 2>&1; then
    fail "restore app compatibility should fail on version mismatch"
  fi
}

test_restore_app_compatibility_check_requires_manifest_apps() {
  if run_libs '
    run_on_node() { return 0; }
    bt_collect_site_apps_json() { printf "[]\n"; }
    entry="{\"apps\":[]}"
    bt_restore_check_app_compatibility "${entry}" local-dev demo.local /tmp/bench
  ' >/dev/null 2>&1; then
    fail "restore app compatibility should fail when manifest has no apps"
  fi
}

test_remove_requires_parameters() {
  if run_libs "bt_load_config '${CONFIG_PATH}'; backup_remove_main --force" >/dev/null 2>&1; then
    fail "remove should require --backup parameter"
  fi
}

test_remove_requires_force_in_non_interactive_mode() {
  local tmp_cache_dir

  tmp_cache_dir="$(mktemp -d)"
  if run_libs "exec </dev/null; BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_remove_1\",\"source_node\":\"local-dev\",\"node_type\":\"frappe-node\",\"source_site\":\"demo.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a-database.sql.gz\",\"site_config\":\"site_config.json\",\"manifest\":\"a-manifest.json\"}}'; backup_remove_main --backup demo_remove_1" >/dev/null 2>&1; then
    fail "remove should require --force in non-interactive mode"
  fi
}

test_remove_cache_only_with_force_removes_entry() {
  local tmp_cache_dir out

  tmp_cache_dir="$(mktemp -d)"
  out="$(run_libs "BT_CACHE_DIR='${tmp_cache_dir}'; BT_CACHE_NODES_DIR='${tmp_cache_dir}/nodes'; BT_CACHE_LEGACY_PATH='${tmp_cache_dir}/cache.jsonl'; bt_load_config '${CONFIG_PATH}'; bt_cache_upsert_entry '{\"backup_id\":\"demo_remove_2\",\"source_node\":\"local-dev\",\"node_type\":\"frappe-node\",\"source_site\":\"demo.local\",\"reason\":\"demo\",\"created_at\":\"2026-01-01T00:00:00Z\",\"complete\":true,\"artifacts\":{\"db_dump\":\"a-database.sql.gz\",\"site_config\":\"site_config.json\",\"manifest\":\"a-manifest.json\"}}'; backup_remove_main --backup demo_remove_2 --cache-only --force >/dev/null; printf 'COUNT=%s\n' \"\$(bt_cache_list_all | jq 'length')\"")"

  assert_contains "${out}" "COUNT=0"
}

test_global_dry_run_scan() {
  local out
  out="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run scan --node local-dev 2>&1)"
  assert_contains "${out}" "Would scan:"
}

test_primary_resource_commands_work() {
  local out_scan out_restore

  out_scan="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run node scan --node local-dev 2>&1)"
  assert_contains "${out_scan}" "Would scan:"

  out_restore="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run backup restore --backup demo_1 --to local-dev --site demo.local 2>&1)"
  assert_contains "${out_restore}" "DRY-RUN: Would restore"
}

test_alias_commands_still_work() {
  local out_scan out_restore

  out_scan="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run scan --node local-dev 2>&1)"
  assert_contains "${out_scan}" "Would scan:"

  out_restore="$("${ROOT_DIR}/bin/backupctl" --config "${CONFIG_PATH}" --dry-run restore --backup demo_1 --to local-dev --site demo.local 2>&1)"
  assert_contains "${out_restore}" "DRY-RUN: Would restore"
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
  test_manifest_json_generation_with_apps
  test_backup_hash_generation
  test_backup_hash_uses_location
  test_backup_is_complete_check
  test_backup_display_name
  test_cache_library_exists
  test_cache_entry_schema_exists
  test_cache_uses_per_node_files_and_aggregates_centrally
  test_cache_prunes_removed_node_files
  test_backup_library_exists
  test_backup_create_can_infer_single_site_from_cache_and_default_reason
  test_backup_create_requires_site_when_multiple_sites_are_known
  test_list_library_exists
  test_copy_library_exists
  test_restore_library_exists
  test_remove_library_exists
  test_copy_requires_parameters
  test_copy_can_infer_from_node_from_cache
  test_copy_uses_cached_location_for_source_and_target_paths
  test_copy_cache_entry_gets_new_hash_and_origin_hash
  test_scan_local_frappe_records_backup_path_and_relative_dir
  test_scan_updates_existing_manifest_hash
  test_list_text_shows_node_instead_of_source_site
  test_restore_requires_parameters
  test_restore_config_mode_validation
  test_restore_app_compatibility_check_passes_on_matching_apps
  test_restore_app_compatibility_check_fails_on_mismatch
  test_restore_app_compatibility_check_requires_manifest_apps
  test_remove_requires_parameters
  test_remove_requires_force_in_non_interactive_mode
  test_remove_cache_only_with_force_removes_entry
  test_global_dry_run_scan
  test_primary_resource_commands_work
  test_alias_commands_still_work
  test_global_dry_run_restore
  printf 'PASS: all tests successful\n'
}

run_all_tests
