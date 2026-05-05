#!/bin/bash

# Cleanup script to remove wildcard DB permissions for testing/debugging.
# Requires env vars: DB_HOST, DB_ROOT_USER, DB_ROOT_PASSWORD

echo "🧹 Cleanup: Removing wildcard permissions..."

# Wait for DB to be ready
echo "⏳ Waiting for database to be ready..."
while ! mysqladmin ping -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" --silent; do
    echo "Waiting for database connection..."
    sleep 2
done
echo "✅ Database is ready"

# Get all Frappe users
echo "🔍 Finding Frappe DB users..."
FRAPPE_USERS=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT DISTINCT user FROM mysql.user WHERE user LIKE '\\_%' AND user != '';" 2>/dev/null)

if [ -z "$FRAPPE_USERS" ]; then
    echo "ℹ️  No Frappe users found"
    exit 0
fi

echo "📋 Found Frappe users: $FRAPPE_USERS"

# Remove wildcard users
for user in $FRAPPE_USERS; do
    echo ""
    echo "🗑️  Processing user: $user"

    # Check if wildcard user exists
    WILDCARD_COUNT=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$user' AND host = '%';" 2>/dev/null)
    echo "  🔍 Wildcard users found: $WILDCARD_COUNT"

    if [ "$WILDCARD_COUNT" != "0" ]; then
        echo "  🗑️  Removing wildcard user: $user@%"
        mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "DROP USER '$user'@'%';" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "    ✅ Wildcard user removed successfully"
        else
            echo "    ❌ Failed to remove wildcard user"
        fi

        # Also remove wildcard permissions from mysql.db
        echo "  🗑️  Removing wildcard database permissions..."
        mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.db WHERE User = '$user' AND Host = '%';" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "    ✅ Wildcard database permissions removed"
        else
            echo "    ❌ Failed to remove wildcard database permissions"
        fi
    else
        echo "  ℹ️  No wildcard user to remove"
    fi

    # Show remaining users
    echo "  📊 Remaining users for $user:"
    mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "SELECT user, host FROM mysql.user WHERE user = '$user';" 2>/dev/null
done

echo ""
echo "🔄 Flushing privileges..."
mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" 2>/dev/null

echo ""
echo "📊 Final verification - remaining Frappe users:"
mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "
SELECT
    user,
    host,
    CASE WHEN host = '%' THEN '✅ WILDCARD' ELSE '📍 SPECIFIC' END as type,
    plugin,
    CASE
        WHEN authentication_string = '' OR authentication_string IS NULL THEN '❌ NO PASSWORD'
        ELSE '✅ HAS PASSWORD'
    END as status
FROM mysql.user
WHERE user LIKE '\\_%' AND user != ''
ORDER BY user, host;
" 2>/dev/null

echo ""
echo "🧪 Testing connection after cleanup..."
for user in $FRAPPE_USERS; do
    SITE_CONFIG_PATH="/home/frappe/frappe-bench/sites/${SITE_NAME}/site_config.json"
    if [ -f "$SITE_CONFIG_PATH" ]; then
        DB_PASSWORD=$(python3 -c "
import json
try:
    with open('$SITE_CONFIG_PATH', 'r') as f:
        config = json.load(f)
    print(config.get('db_password', ''))
except:
    pass
" 2>/dev/null)

        if [ -n "$DB_PASSWORD" ]; then
            echo "🔌 Testing $user connection after cleanup..."
            if mysql -h "$DB_HOST" -u "$user" -p"$DB_PASSWORD" -e "SELECT 1;" 2>/dev/null >/dev/null; then
                echo "  ✅ Connection still works (from current IP)"
            else
                echo "  ❌ Connection failed (expected - no wildcard)"
            fi
        fi
    fi
    break # Only test first user
done

echo "🎉 Cleanup completed!"
