#!/usr/bin/env bash

bt_backup_model_definition() {
  cat <<'EOM'
Backup Object:
  backup_id: string (unique identifier)
  source_node: string (node id from config)
  node_type: string (frappe-node | plain-dir)
  source_site: string (site name, e.g. erp.customer-a.de)
  backup_path: string (configured node backup_path used during scan)
  source_rel_dir: string (backup directory relative to backup_path)
  backup_hash: string (short hash of backup_id plus concrete location)
  origin_backup_hash: string (optional, source copy hash for copied backups)
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

  digest="$(bt_sha256_short "${backup_id}")"
  printf '%s\n' "${digest}"
}

bt_sha256_short() {
  local value="$1"
  local digest

  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(printf '%s' "${value}" | sha256sum | awk '{print $1}')"
  else
    digest="$(printf '%s' "${value}" | shasum -a 256 | awk '{print $1}')"
  fi

  printf '%s\n' "${digest}" | cut -c1-6
}

bt_backup_hash_from_object() {
  local backup_obj_json="$1"
  local hash_input

  hash_input="$(jq -r '
    [
      (.backup_id // ""),
      (.source_node // ""),
      (.backup_path // ""),
      (.source_rel_dir // "")
    ] | @tsv
  ' <<<"${backup_obj_json}")"

  bt_sha256_short "${hash_input}"
}

bt_backup_with_hash() {
  local backup_obj_json="$1"
  local backup_id backup_hash

  backup_id="$(jq -r '.backup_id // empty' <<<"${backup_obj_json}")"
  if [[ -z "${backup_id}" ]]; then
    printf '%s\n' "${backup_obj_json}"
    return
  fi

  backup_hash="$(bt_backup_hash_from_object "${backup_obj_json}")"
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
  local created_at_override="${7:-}"
  local apps_json="${8:-[]}"
  local created_at
  local backup_hash
  
  created_at="${created_at_override:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
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
    --argjson apps "${apps_json:-[]}" \
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
      apps: $apps,
      complete: true
    }'
}

bt_collect_site_apps_json() {
  local node_id="$1"
  local site="$2"
  local bench_path="$3"
  local py_script cmd apps_json

  py_script="$(cat <<'PY'
import json
import os
import re
import subprocess
import sys

bench_path = sys.argv[1]
site = sys.argv[2]
apps_file = os.path.join(bench_path, "sites", site, "apps.txt")

if not os.path.isfile(apps_file):
    print("[]")
    raise SystemExit(0)

def run(cmd, cwd=None):
    try:
        return subprocess.check_output(cmd, cwd=cwd, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""

def parse_version(app_dir, app_name):
    pyproject = os.path.join(app_dir, "pyproject.toml")
    if os.path.isfile(pyproject):
        try:
            import tomllib
            with open(pyproject, "rb") as f:
                data = tomllib.load(f)
            version = ((data.get("project") or {}).get("version") or "").strip()
            if version:
                return version
        except Exception:
            pass

    hooks_py = os.path.join(app_dir, app_name, "hooks.py")
    if os.path.isfile(hooks_py):
        try:
            txt = open(hooks_py, "r", encoding="utf-8").read()
            m = re.search(r"app_version\\s*=\\s*['\"]([^'\"]+)['\"]", txt)
            if m:
                return m.group(1).strip()
        except Exception:
            pass

    init_py = os.path.join(app_dir, app_name, "__init__.py")
    if os.path.isfile(init_py):
        try:
            txt = open(init_py, "r", encoding="utf-8").read()
            m = re.search(r"__version__\\s*=\\s*['\"]([^'\"]+)['\"]", txt)
            if m:
                return m.group(1).strip()
        except Exception:
            pass

    return ""

apps = []
with open(apps_file, "r", encoding="utf-8") as f:
    for line in f:
        app = line.strip()
        if not app or app.startswith("#"):
            continue
        apps.append(app)

result = []
for app in apps:
    app_dir = os.path.join(bench_path, "apps", app)
    entry = {"app": app}

    version = parse_version(app_dir, app)
    if version:
        entry["version"] = version

    branch = run(["git", "-C", app_dir, "rev-parse", "--abbrev-ref", "HEAD"])
    if branch and branch != "HEAD":
        entry["branch"] = branch

    commit = run(["git", "-C", app_dir, "rev-parse", "--short", "HEAD"])
    if commit:
        entry["commit"] = commit

    result.append(entry)

result.sort(key=lambda x: x.get("app", ""))
print(json.dumps(result, separators=(",", ":")))
PY
)"

  cmd="python3 -c $(bt_quote "${py_script}") $(bt_quote "${bench_path}") $(bt_quote "${site}")"
  apps_json="$(run_on_node "${node_id}" "${cmd}" 2>/dev/null || true)"

  if [[ -z "${apps_json}" ]] || ! jq -e 'type == "array"' <<<"${apps_json}" >/dev/null 2>&1; then
    apps_json='[]'
  fi

  printf '%s\n' "${apps_json}"
}

# Enriches a manifest/backup JSON with node-location metadata,
# identical to what bt_scan_remote_manifests produces.
# Args: manifest_json  node_id  node_type  backup_root  backup_dir
bt_manifest_add_node_meta() {
  local manifest_json="$1"
  local node_id="$2"
  local node_type="$3"
  local backup_root="$4"
  local backup_dir="$5"

  local rel_dir
  rel_dir="${backup_dir#"${backup_root%/}/"}"
  [[ "${rel_dir}" == "${backup_dir}" ]] && rel_dir=""

  jq -c \
    --arg node "${node_id}" \
    --arg nt "${node_type}" \
    --arg bp "${backup_root}" \
    --arg rd "${rel_dir}" \
    '. + {source_node: $node, node_type: $nt, backup_path: $bp, source_rel_dir: $rd}' \
    <<<"${manifest_json}"
}

bt_backup_is_complete() {
  local backup_obj_json="$1"
  
  jq -e '.complete == true and (.artifacts | has("db_dump") and has("site_config"))' <<<"${backup_obj_json}" >/dev/null
}

bt_backup_display_name() {
  local backup_obj_json="$1"
  
  jq -r '.display_name // .reason // .backup_id' <<<"${backup_obj_json}"
}
