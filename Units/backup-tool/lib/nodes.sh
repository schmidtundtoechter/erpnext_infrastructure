#!/usr/bin/env bash

bt_node_runtime_model() {
  cat <<'EOM'
source_kind:
  - frappe-backup-dir
  - plain-backup-dir

access_type:
  - local
  - local-docker
  - ssh-host
  - ssh-docker
EOM
}

bt_quote() {
  printf '%q' "$1"
}

bt_build_ssh_base_cmd() {
  local node_json="$1"
  local host user port

  host="$(jq -r '.host' <<<"${node_json}")"
  user="$(jq -r '.user' <<<"${node_json}")"
  port="$(jq -r '.port // 22' <<<"${node_json}")"

  printf 'ssh -o BatchMode=yes -o ConnectTimeout=10 -p %s %s@%s' "${port}" "${user}" "${host}"
}

bt_wrap_docker_exec_command() {
  local node_json="$1"
  local inner_command="$2"
  local container compose_service

  container="$(jq -r '.container // empty' <<<"${node_json}")"
  compose_service="$(jq -r '.compose_service // empty' <<<"${node_json}")"

  if [[ -n "${compose_service}" ]]; then
    printf 'docker compose exec -T %s bash -lc %s' "$(bt_quote "${compose_service}")" "$(bt_quote "${inner_command}")"
    return
  fi

  if [[ -n "${container}" ]]; then
    printf 'docker exec -i %s bash -lc %s' "$(bt_quote "${container}")" "$(bt_quote "${inner_command}")"
    return
  fi

  bt_die "Docker access requires container or compose_service"
}

bt_build_run_command() {
  local node_id="$1"
  local command="$2"
  local node_json access_type ssh_base docker_wrapped

  node_json="$(bt_get_node_json "${node_id}")"
  access_type="$(jq -r '.access_type' <<<"${node_json}")"

  case "${access_type}" in
    local)
      printf '%s' "${command}"
      ;;
    local-docker)
      bt_wrap_docker_exec_command "${node_json}" "${command}"
      ;;
    ssh-host)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      printf '%s %s' "${ssh_base}" "$(bt_quote "${command}")"
      ;;
    ssh-docker)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      docker_wrapped="$(bt_wrap_docker_exec_command "${node_json}" "${command}")"
      printf '%s %s' "${ssh_base}" "$(bt_quote "${docker_wrapped}")"
      ;;
    *)
      bt_die "Unsupported access_type: ${access_type}"
      ;;
  esac
}

run_on_node() {
  local node_id="$1"
  local command="$2"
  local runner_cmd

  runner_cmd="$(bt_build_run_command "${node_id}" "${command}")"

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    printf '%s\n' "${runner_cmd}"
    return 0
  fi

  eval "${runner_cmd}"
}

bt_check_node_reachability() {
  local node_id="$1"
  local node_json access_type ssh_base

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    return 0
  fi

  node_json="$(bt_get_node_json "${node_id}")"
  access_type="$(jq -r '.access_type' <<<"${node_json}")"

  case "${access_type}" in
    local)
      return 0
      ;;
    local-docker)
      command -v docker >/dev/null 2>&1
      ;;
    ssh-host|ssh-docker)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      eval "${ssh_base} true" >/dev/null 2>&1
      ;;
    *)
      bt_die "Unsupported access_type for reachability: ${access_type}"
      ;;
  esac
}

bt_node_path_spec() {
  local node_id="$1"
  local path="$2"
  local node_json access_type host user

  node_json="$(bt_get_node_json "${node_id}")"
  access_type="$(jq -r '.access_type' <<<"${node_json}")"

  case "${access_type}" in
    local|local-docker)
      printf '%s' "${path}"
      ;;
    ssh-host|ssh-docker)
      host="$(jq -r '.host' <<<"${node_json}")"
      user="$(jq -r '.user' <<<"${node_json}")"
      printf '%s@%s:%s' "${user}" "${host}" "${path}"
      ;;
    *)
      bt_die "Unsupported access_type for path spec: ${access_type}"
      ;;
  esac
}

build_transfer_command() {
  local from_node="$1"
  local to_node="$2"
  local source_path="$3"
  local target_path="$4"
  local src_spec dst_spec

  src_spec="$(bt_node_path_spec "${from_node}" "${source_path}")"
  dst_spec="$(bt_node_path_spec "${to_node}" "${target_path}")"
  printf 'rsync -a --partial --progress %s %s' "$(bt_quote "${src_spec}")" "$(bt_quote "${dst_spec}")"
}

nodes_list() {
  bt_require_loaded_config
  jq -r '.nodes[] | [.id, .source_kind, .access_type, (.enabled // true)] | @tsv' "${BT_CONFIG_PATH}"
}
