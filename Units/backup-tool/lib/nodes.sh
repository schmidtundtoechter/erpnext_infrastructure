#!/usr/bin/env bash

bt_node_runtime_model() {
  cat <<'EOM'
node_type:
  - frappe-node
  - plain-dir

access:
  - local
  - docker
  - ssh
  - ssh-docker
EOM
}

bt_quote() {
  printf '%q' "$1"
}

bt_docker_local_context() {
  local node_json="$1"
  local node_context

  node_context="$(jq -r '.docker_context // empty' <<<"${node_json}")"
  if [[ -n "${node_context}" ]]; then
    printf '%s' "${node_context}"
    return
  fi

  printf '%s' "${BT_DOCKER_LOCAL_CONTEXT:-default}"
}

bt_ensure_local_docker_context() {
  local node_json="$1"
  local expected current

  command -v docker >/dev/null 2>&1 || bt_die "docker not found for docker node"

  expected="$(bt_docker_local_context "${node_json}")"
  current="$(docker context show 2>/dev/null || true)"

  [[ -n "${current}" ]] || bt_die "Could not detect current docker context"

  if [[ "${current}" != "${expected}" ]]; then
    bt_die "Docker context mismatch: expected '${expected}', current '${current}'. Set correct context or configure node.docker_context."
  fi
}

bt_wrap_local_docker_command() {
  local node_json="$1"
  local inner_command="$2"
  local context container compose_service

  context="$(bt_docker_local_context "${node_json}")"
  container="$(jq -r '.container // empty' <<<"${node_json}")"
  compose_service="$(jq -r '.compose_service // empty' <<<"${node_json}")"

  if [[ -n "${compose_service}" ]]; then
    printf 'docker --context %s compose exec -T %s bash -lc %s' \
      "$(bt_quote "${context}")" \
      "$(bt_quote "${compose_service}")" \
      "$(bt_quote "${inner_command}")"
    return
  fi

  if [[ -n "${container}" ]]; then
    printf 'docker --context %s exec -i %s bash -lc %s' \
      "$(bt_quote "${context}")" \
      "$(bt_quote "${container}")" \
      "$(bt_quote "${inner_command}")"
    return
  fi

  bt_die "Docker access requires container or compose_service"
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
  local node_json access ssh_base docker_wrapped

  node_json="$(bt_get_node_json "${node_id}")"
  access="$(jq -r '.access' <<<"${node_json}")"

  case "${access}" in
    local)
      printf '%s' "${command}"
      ;;
    docker)
      bt_wrap_local_docker_command "${node_json}" "${command}"
      ;;
    ssh)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      printf '%s %s' "${ssh_base}" "$(bt_quote "${command}")"
      ;;
    ssh-docker)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      docker_wrapped="$(bt_wrap_docker_exec_command "${node_json}" "${command}")"
      printf '%s %s' "${ssh_base}" "$(bt_quote "${docker_wrapped}")"
      ;;
    *)
      bt_die "Unsupported access: ${access}"
      ;;
  esac
}

run_on_node() {
  local node_id="$1"
  local command="$2"
  local runner_cmd node_json access

  runner_cmd="$(bt_build_run_command "${node_id}" "${command}")"

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    printf '%s\n' "${runner_cmd}"
    return 0
  fi

  node_json="$(bt_get_node_json "${node_id}")"
  access="$(jq -r '.access' <<<"${node_json}")"
  if [[ "${access}" == "docker" ]]; then
    bt_ensure_local_docker_context "${node_json}"
  fi

  eval "${runner_cmd}"
}

bt_check_node_reachability() {
  local node_id="$1"
  local node_json access ssh_base

  if [[ "${BT_RUNNER_MODE:-execute}" == "dry-run" ]]; then
    return 0
  fi

  node_json="$(bt_get_node_json "${node_id}")"
  access="$(jq -r '.access' <<<"${node_json}")"

  case "${access}" in
    local)
      return 0
      ;;
    docker)
      bt_ensure_local_docker_context "${node_json}"
      docker ps >/dev/null 2>&1
      ;;
    ssh|ssh-docker)
      ssh_base="$(bt_build_ssh_base_cmd "${node_json}")"
      eval "${ssh_base} true" >/dev/null 2>&1
      ;;
    *)
      bt_die "Unsupported access for reachability: ${access}"
      ;;
  esac
}

bt_node_path_spec() {
  local node_id="$1"
  local path="$2"
  local node_json access host user

  node_json="$(bt_get_node_json "${node_id}")"
  access="$(jq -r '.access' <<<"${node_json}")"

  case "${access}" in
    local|docker)
      printf '%s' "${path}"
      ;;
    ssh|ssh-docker)
      host="$(jq -r '.host' <<<"${node_json}")"
      user="$(jq -r '.user' <<<"${node_json}")"
      printf '%s@%s:%s' "${user}" "${host}" "${path}"
      ;;
    *)
      bt_die "Unsupported access for path spec: ${access}"
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
  printf '%-25s %-22s %-16s %s\n' "NODE_ID" "NODE_TYPE" "ACCESS" "ENABLED"
  printf '%s\n' "$(printf '=%.0s' {1..80})"
  jq -r '
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
    .nodes[]
    | [.id, ((.node_type // .source_kind // "?") | normalize_node_type), ((.access // .access_type // "?") | normalize_access), (.enabled // true | tostring)]
    | @tsv
  ' "${BT_CONFIG_PATH}" \
    | awk -F'\t' '{ printf "%-25s %-22s %-16s %s\n", $1, $2, $3, $4 }'
}
