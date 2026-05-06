#!/usr/bin/env bash

bt_backup_model_definition() {
  cat <<'EOM'
Backup Object:
  backup_id: string (unique identifier)
  source_node: string (node id from config)
  node_type: string (frappe-node | plain-dir)
  source_site: string (site name, e.g. erp.customer-a.de)
  created_at: string (ISO 8601 timestamp)
  reason: string (fachlicher Grund des Backups)
  tags: array of strings (optional)
  artifacts: object (physical file references)
  complete: boolean (all expected files present)

Artifacts:
  db_dump: string (filename or path)
  public_files: string (filename or path, optional)
  private_files: string (filename or path, optional)
  site_config: string (filename or path)
  manifest: string (filename: manifest.json)
  checksums: string (filename: checksums.sha256)
  apps: string (filename: apps.json)

Manifest Schema (manifest.json):
{
  "backup_id": "string (required)",
  "created_at": "string ISO 8601 (required)",
  "source_node": "string (required)",
  "source_site": "string (required)",
  "backup_type": "string (required, e.g. full-with-files)",
  "reason": "string (required)",
  "display_name": "string (optional, defaults to reason)",
  "tags": "array of strings (optional)",
  "artifacts": "object (required)",
  "checksums": "object (optional, { filename: sha256 })",
  "apps": "array (optional, installed apps and versions)",
  "notes": "string (optional)",
  "created_by": "string (optional)",
  "complete": "boolean (required)"
}
EOM
}

bt_generate_backup_id() {
  local node_id="$1"
  local site="$2"
  local timestamp
  timestamp="$(date -u +%s)"
  printf '%s_%s_%s\n' "${node_id}" "${site}" "${timestamp}"
}

bt_backup_hash_from_id() {
  local backup_id="$1"
  local digest

  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(printf '%s' "${backup_id}" | sha256sum | awk '{print $1}')"
  else
    digest="$(printf '%s' "${backup_id}" | shasum -a 256 | awk '{print $1}')"
  fi

  printf '%s\n' "${digest}" | cut -c1-6
}

bt_backup_with_hash() {
  local backup_obj_json="$1"
  local backup_id backup_hash

  backup_id="$(jq -r '.backup_id // empty' <<<"${backup_obj_json}")"
  if [[ -z "${backup_id}" ]]; then
    printf '%s\n' "${backup_obj_json}"
    return
  fi

  backup_hash="$(bt_backup_hash_from_id "${backup_id}")"
  jq -c --arg h "${backup_hash}" '. + {backup_hash: $h}' <<<"${backup_obj_json}"
}

bt_validate_manifest_json() {
  local manifest_path="$1"
  
  [[ -f "${manifest_path}" ]] || bt_die "Manifest not found: ${manifest_path}"
  
  jq -e . "${manifest_path}" >/dev/null || bt_die "Invalid JSON in manifest: ${manifest_path}"
  
  jq -e '
    (.backup_id | type == "string" and length > 0)
    and (.created_at | type == "string" and length > 0)
    and (.source_node | type == "string" and length > 0)
    and (.source_site | type == "string" and length > 0)
    and (.backup_type | type == "string" and length > 0)
    and (.reason | type == "string" and length > 0)
    and (.artifacts | type == "object")
    and (.complete | type == "boolean")
  ' "${manifest_path}" >/dev/null || bt_die "Manifest validation failed: missing required fields"
}

bt_generate_manifest_json() {
  local backup_id="$1"
  local source_node="$2"
  local source_site="$3"
  local reason="$4"
  local artifacts_json="$5"
  local tags_json="${6:-}"
  local created_at
  local backup_hash
  
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  backup_hash="$(bt_backup_hash_from_id "${backup_id}")"
  
  jq -n \
    --arg bid "${backup_id}" \
    --arg bh "${backup_hash}" \
    --arg node "${source_node}" \
    --arg site "${source_site}" \
    --arg reason "${reason}" \
    --arg ts "${created_at}" \
    --argjson artifacts "${artifacts_json}" \
    --argjson tags "${tags_json:-[]}" \
    '{
      backup_id: $bid,
      backup_hash: $bh,
      created_at: $ts,
      source_node: $node,
      source_site: $site,
      backup_type: "full-with-files",
      reason: $reason,
      display_name: $reason,
      tags: $tags,
      artifacts: $artifacts,
      complete: true
    }'
}

bt_backup_is_complete() {
  local backup_obj_json="$1"
  
  jq -e '.complete == true and (.artifacts | has("db_dump") and has("site_config"))' <<<"${backup_obj_json}" >/dev/null
}

bt_backup_display_name() {
  local backup_obj_json="$1"
  
  jq -r '.display_name // .reason // .backup_id' <<<"${backup_obj_json}"
}
