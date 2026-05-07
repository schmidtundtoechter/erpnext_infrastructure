#!/bin/bash

SITE_NAME=$1
SCENARIO_INSTALL_APPS=$2
UPGRADE_MARKER="sites/.run-app-upgrade"
if [ -z "$SCENARIO_INSTALL_APPS" -o -z "$SITE_NAME" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 <site-name> <install-apps>"
    exit 1
fi

# Normalize input to a single APPS_JSON file.
# Modern path: SCENARIO_INSTALL_APPS is a .json filename (mounted at /tmp/<file>).
# Legacy path: inline comma-separated app@url@version strings (deprecated).
#   Legacy hacks supported during conversion:
#     -appname    -> active: false  (uninstall)
#     url__at__x  -> url@x         (literal @ in SSH URLs)
if [[ "$SCENARIO_INSTALL_APPS" == *.json ]]; then
    APPS_JSON="$SCENARIO_INSTALL_APPS"
    if [[ "$APPS_JSON" != */* ]]; then
        APPS_JSON="/tmp/$APPS_JSON"
    fi
    if [ ! -f "$APPS_JSON" ]; then
        echo "Error: Apps JSON file not found: $APPS_JSON"
        exit 1
    fi
    echo "--iua- Using apps JSON file: $APPS_JSON"
else
    echo "--iua- DEPRECATED: SCENARIO_INSTALL_APPS inline format detected."
    echo "--iua- Migrate to an apps.json file and set SCENARIO_INSTALL_APPS=apps.json."
    APPS_JSON=$(mktemp /tmp/apps_XXXXXX.json)
    IFS=',' read -r -a _legacy_apps <<< "$SCENARIO_INSTALL_APPS"
    _json="["
    for _i in "${!_legacy_apps[@]}"; do
        _app="${_legacy_apps[$_i]}"
        _n=$(echo "$_app" | cut -d'@' -f1)
        _u=$(echo "$_app" | cut -d'@' -f2 | sed 's/__at__/@/g')
        _v=$(echo "$_app" | cut -d'@' -f3)
        _active="true"
        if [[ "$_n" == -* ]]; then
            _active="false"
            _n="${_n:1}"
        fi
        _comma=","
        [ $_i -eq $((${#_legacy_apps[@]}-1)) ] && _comma=""
        _json+=$'\n'"  {\"name\": \"$_n\", \"url\": \"$_u\", \"version\": \"$_v\", \"active\": $_active}$_comma"
    done
    _json+=$'\n'"]"
    echo "$_json" > "$APPS_JSON"
    echo "--iua- Converted to JSON (save as apps.json to remove this warning):"
    cat "$APPS_JSON"
fi

apps_installed=()
site_changed=0
upgrade_failed=0

echo "Calling $0 in site $SITE_NAME"

APP_MANAGEMENT_MODE="reconcile"
if [ -f "$UPGRADE_MARKER" ]; then
    APP_MANAGEMENT_MODE="upgrade"
fi
echo "--iua- App management mode: $APP_MANAGEMENT_MODE"

function is_app_installed_on_site() {
    local app=$1
    bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -q "^$app"
}

function install_app_on_site_if_missing() {
    local app=$1

    if is_app_installed_on_site "$app"; then
        echo "$app is already installed on site, skipping install-app"
    else
        bench --site "${SITE_NAME}" install-app "$app"
        if [ $? -eq 0 ]; then
            echo "$app app installed successfully"
            site_changed=1
        else
            echo "Error installing $app app, retrying with --force"
            if bench --site "${SITE_NAME}" install-app --force "$app"; then
                site_changed=1
            else
                echo "Error installing $app app (force retry failed)"
                if [[ "$APP_MANAGEMENT_MODE" == "upgrade" ]]; then
                    upgrade_failed=1
                fi
                return 1
            fi
        fi
    fi
}

# Reconcile mode: install missing active apps only. Existing apps are not fetched,
# checked out, reset, or upgraded.
function reconcile_app() {
    repo=$1
    app=$2
    version=$3

    echo "Reconciling $app app from $repo"

    if [ ! -d "apps/$app" ]; then
        echo "Installing missing $app app at version $version"
        bench get-app "$app" "$repo" --branch "$version"
        site_changed=1
    else
        echo "$app app directory already exists, leaving code unchanged"
    fi

    install_app_on_site_if_missing "$app"

    # Keep active apps in desired state to prevent accidental cleanup on inconsistent checks.
    apps_installed+=($app)
}

# Upgrade mode: install missing apps and move existing apps to the configured ref.
function upgrade_app() {
    repo=$1
    app=$2
    version=$3

    echo "Installing or upgrading $app app from $repo"

    # Get or update app
    # Get base of repot without the ending ".git"
    if [ ! -d apps/$app ]; then
        echo "Installing $app app"
        bench get-app $app $repo --branch $version
        site_changed=1
    fi

    # Fix git refs to ensure all remote branches/tags are fetchable
    if [ -f /home/frappe/frappe-bench/fix-git-refs.sh ]; then
        /home/frappe/frappe-bench/fix-git-refs.sh apps/$app || true
    fi

    echo "Updating $app app to version $version"
    pushd apps/$app > /dev/null

    # TODO: Hier sollte bench update bevorzugt werden, damit apps.json und requirements.txt auch aktualisiert werden
	# TODO: Hier ist auch unklar, warum erpnext und frappe kein .git Verzeichnis haben
	# TODO: auch bench und pip und das betriebssystem (in alle containern) sollte geupdatet werden
	# TODO: Check /var/run/docker.sock permissions if docker commands fail
	# TODO: Wenn die python version wechselt, müssen die envs neu gebaut werden!

    # Resolve the app remote dynamically (usually origin) and reuse it consistently.
    app_remote=$(git remote | head -n 1)
    if [ -z "$app_remote" ]; then
        echo "--iua- No git remote configured for $app; skipping remote-based fetch/reset"
        if ! git checkout "$version"; then
            echo "--iua- Could not checkout $version for $app without remote, continuing without checkout"
        fi
    else
        app_remote_url=$(git remote get-url "$app_remote" 2>/dev/null || echo "<unknown>")
        echo "--iua- Using git remote '$app_remote' ($app_remote_url) for $app"

        # Check ref already available in remotes or tags
        if git show-ref --verify --quiet refs/remotes/$app_remote/$version; then
            echo "Ref $version already exists in remotes/$app_remote"
        elif git show-ref --verify --quiet refs/tags/$version; then
            echo "Ref $version already exists in tags"
        else
            echo "Adding refs"
            git config --add remote.$app_remote.fetch "+refs/heads/$version:refs/remotes/$app_remote/$version"
            git config --add remote.$app_remote.fetch "+refs/tags/$version:refs/tags/$version"
        fi
        if git fetch "$app_remote" "$version"; then
            if ! git checkout "$version"; then
                echo "--iua- git checkout $version failed for $app after successful fetch, continuing"
            fi
            # For branch refs: reset working copy to the fetched remote HEAD so we actually update.
            # Tags and commit hashes are already pinned by checkout and do not need a reset.
            if git show-ref --verify --quiet refs/remotes/$app_remote/$version; then
                git reset --hard "$app_remote/$version"
                echo "--iua- Reset $app to $app_remote/$version (latest fetched commit)"
            else
                echo "--iua- $version is a tag or pinned ref — checkout is sufficient, no reset needed"
            fi
        else
            echo "--iua- git fetch $app_remote $version failed for $app; skipping remote-based update"
        fi
    fi
    popd > /dev/null

    install_app_on_site_if_missing "$app"

    # Keep active apps in desired state to prevent accidental cleanup on inconsistent checks.
    apps_installed+=($app)
}

function remove_app() {
	app_name=$1
    is_installed_on_site=0
    if is_app_installed_on_site "$app_name"; then
        is_installed_on_site=1
    fi

	# Remove app from site DB
    if [ $is_installed_on_site -eq 1 ]; then
        echo "Uninstalling $app_name app from site ${SITE_NAME}"
        if ! bench --site ${SITE_NAME} uninstall-app -y "$app_name"; then
            echo "--iua- uninstall-app failed for $app_name, trying remove-from-installed-apps"
            bench --site ${SITE_NAME} remove-from-installed-apps "$app_name" || true
        fi

		# Remove app from bench (bench remove-app may fail if bench still thinks app is installed;
		# we fall through to manual cleanup regardless)
		echo "Removing $app_name app from apps directory"
		if [ -d "apps/$app_name" ]; then
			bench remove-app "$app_name" || echo "--iua- bench remove-app $app_name failed (non-fatal), cleaning up manually"
		else
			echo "--iua- app directory apps/$app_name not found, skipping bench remove-app"
		fi

		# Force-clean sites/apps.txt (use grep -v to avoid sed -i issues on volume filesystems)
		echo "Removing $app_name from sites/apps.txt"
		if [ -f sites/apps.txt ]; then
			grep -v "^${app_name}$" sites/apps.txt > /tmp/apps_clean.txt && mv /tmp/apps_clean.txt sites/apps.txt || true
		fi

		# Force remove app directory and archived copy
		echo "Force removing $app_name directory"
		rm -rf apps/$app_name
		rm -rf archived/apps/${app_name}-*
        site_changed=1
    else
        echo "--iua- $app_name not installed on site, skipping uninstall-app"
    fi
}

echo "--iua- Processing apps from: $APPS_JSON"

# Add default apps (always kept)
apps_installed+=(frappe)
apps_installed+=(erpnext)

# Process apps from JSON: active=true (default) -> install/update; active=false -> remove
while IFS=$'\t' read -r app_name app_url app_version app_active; do
    if [[ "$app_active" == "false" ]]; then
        echo "--iua- Removing app $app_name (active=false)"
        remove_app "$app_name"
    else
        if [[ "$APP_MANAGEMENT_MODE" == "upgrade" ]]; then
            upgrade_app "$app_url" "$app_name" "$app_version"
        else
            reconcile_app "$app_url" "$app_name" "$app_version"
        fi
    fi
done < <(jq -r '.[] | [.name, .url, .version, (if .active == false then false else true end | tostring)] | @tsv' "$APPS_JSON")

echo "--iua- Active apps kept: ${apps_installed[@]}"

# Remove other apps
echo "--iua- Removing other apps that are not in active apps JSON"
for app in apps/*/; do
    [ -d "$app" ] || continue
	app_name=$(basename "$app")
	if [[ ! " ${apps_installed[@]} " =~ " ${app_name} " ]]; then
		remove_app "$app_name"
	else
		echo "Keeping $app_name app"
	fi
done

if [[ "$APP_MANAGEMENT_MODE" == "upgrade" ]]; then
    # Update requirements
    echo "--iua- Updating requirements"
    # TODO: Fix error messages when erpnext or frappe are not on a branch
    if ! bench update --requirements; then
        upgrade_failed=1
    fi

    # Ensure pkg_resources is available for frappe integrations during migrate.
    echo "--iua- Ensuring setuptools/pkg_resources is available"
    if ! /home/frappe/frappe-bench/env/bin/python -m pip install --quiet --upgrade setuptools wheel; then
        upgrade_failed=1
    fi
    if ! /home/frappe/frappe-bench/env/bin/python -c "import pkg_resources" >/dev/null 2>&1; then
        echo "--iua- pkg_resources still missing, retrying with setuptools<81"
        uv pip install --quiet --python /home/frappe/frappe-bench/env/bin/python "setuptools<81" || \
          /home/frappe/frappe-bench/env/bin/python -m pip install --quiet "setuptools<81" || \
          upgrade_failed=1
    fi
    if ! /home/frappe/frappe-bench/env/bin/python -c "import pkg_resources" >/dev/null 2>&1; then
        echo "Error: pkg_resources is still missing after setuptools repair"
        upgrade_failed=1
    fi

    # Migrate site
    echo "--iua- Migrating site ${SITE_NAME}"
    if ! bench --site ${SITE_NAME} migrate; then
        upgrade_failed=1
    fi

    # Rebuild assets
    echo "--iua- Rebuilding assets"
    # TODO: Optimize, needs many resources
    #bench build

    # Set developer mode
    echo "--iua- Setting developer mode and server script enabled"
    bench set-config -g developer_mode 1 || upgrade_failed=1
    bench set-config -g server_script_enabled 1 || upgrade_failed=1
    bench setup requirements --dev || upgrade_failed=1

    # Clear cache
    echo "--iua- Clearing cache"
    bench --site ${SITE_NAME} clear-cache || upgrade_failed=1
    bench --site ${SITE_NAME} clear-website-cache || upgrade_failed=1

    if [ "$upgrade_failed" -eq 0 ]; then
        echo "--iua- Upgrade completed, removing marker $UPGRADE_MARKER"
        rm -f "$UPGRADE_MARKER"
    else
        echo "--iua- Upgrade failed, keeping marker $UPGRADE_MARKER for retry"
        exit 1
    fi
else
    if [ "$site_changed" -eq 1 ]; then
        echo "--iua- Site install state changed, migrating site ${SITE_NAME}"
        bench --site ${SITE_NAME} migrate

        echo "--iua- Clearing cache"
        bench --site ${SITE_NAME} clear-cache
        bench --site ${SITE_NAME} clear-website-cache
    else
        echo "--iua- Reconcile completed without install-state changes; skipping migrate and cache clear"
    fi
fi

# All containers need to restart after installation: This is done in create-site container startup script
