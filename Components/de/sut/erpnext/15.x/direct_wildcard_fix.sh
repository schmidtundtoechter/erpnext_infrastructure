#!/bin/bash

# Direct wildcard user creation for Frappe DB
# Fixes IP-change issues where MySQL users are bound to specific container IPs.
# Requires env vars: DB_HOST, DB_ROOT_USER, DB_ROOT_PASSWORD

echo "🔧 Direct wildcard user creation..."

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

# Process each user
for user in $FRAPPE_USERS; do
    echo ""
    echo "🔧 Processing user: $user"

    # Get all current hosts for this user
    USER_HOSTS=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT host FROM mysql.user WHERE user = '$user';" 2>/dev/null)
    echo "  📍 Current hosts: $USER_HOSTS"

    # Check for wildcard and if it has a password
    WILDCARD_COUNT=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$user' AND host = '%';" 2>/dev/null)
    WILDCARD_HAS_PASSWORD=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$user' AND host = '%' AND (authentication_string != '' AND authentication_string IS NOT NULL);" 2>/dev/null)
    echo "  🔍 Wildcard count: $WILDCARD_COUNT"
    echo "  🔑 Wildcard has password: $WILDCARD_HAS_PASSWORD"

    # Get first specific host to clone from (prefer non-wildcard with password)
    TEMPLATE_HOST=$(echo "$USER_HOSTS" | grep -v "^%$" | head -1)
    if [ -z "$TEMPLATE_HOST" ]; then
        TEMPLATE_HOST=$(echo "$USER_HOSTS" | head -1)
    fi
    echo "  📋 Template host: $TEMPLATE_HOST"

    if [ "$WILDCARD_COUNT" = "0" ] || [ "$WILDCARD_HAS_PASSWORD" = "0" ]; then
        if [ "$WILDCARD_COUNT" = "0" ]; then
            echo "  ➕ Creating wildcard user..."
        else
            echo "  🔄 Wildcard user exists but has no password - fixing..."
            # Drop the broken wildcard user first
            mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "DROP USER IF EXISTS '$user'@'%';" 2>/dev/null
        fi

        # Get user info from template
        USER_INFO=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "SELECT authentication_string, plugin FROM mysql.user WHERE user = '$user' AND host = '$TEMPLATE_HOST';" 2>/dev/null | tail -1)
        PASSWORD_HASH=$(echo "$USER_INFO" | awk '{print $1}')
        AUTH_PLUGIN=$(echo "$USER_INFO" | awk '{print $2}')

        echo "  🔑 Password hash length: ${#PASSWORD_HASH}"
        echo "  🔑 Password hash: ${PASSWORD_HASH:0:20}..."
        echo "  🔌 Auth plugin: $AUTH_PLUGIN"

        if [ -z "$PASSWORD_HASH" ] || [ "$PASSWORD_HASH" = "authentication_string" ] || [ "$PASSWORD_HASH" = "NULL" ]; then
            echo "    ❌ Could not get password hash from template host"
            continue
        fi

        if [ -n "$PASSWORD_HASH" ]; then
            # Create wildcard user - try direct table insertion first (more reliable)
            echo "  📝 Using direct table insertion method..."

            mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "
            INSERT INTO mysql.user
            (user, host, authentication_string, plugin, ssl_cipher, x509_issuer, x509_subject,
             max_questions, max_updates, max_connections, max_user_connections,
             Select_priv, Insert_priv, Update_priv, Delete_priv, Create_priv, Drop_priv,
             Reload_priv, Shutdown_priv, Process_priv, File_priv, Grant_priv, References_priv,
             Index_priv, Alter_priv, Show_db_priv, Super_priv, Create_tmp_table_priv,
             Lock_tables_priv, Execute_priv, Repl_slave_priv, Repl_client_priv, Create_view_priv,
             Show_view_priv, Create_routine_priv, Alter_routine_priv, Create_user_priv,
             Event_priv, Trigger_priv, Create_tablespace_priv)
            SELECT
                user,
                '%' as host,
                authentication_string,
                plugin,
                ssl_cipher,
                x509_issuer,
                x509_subject,
                max_questions,
                max_updates,
                max_connections,
                max_user_connections,
                Select_priv, Insert_priv, Update_priv, Delete_priv, Create_priv, Drop_priv,
                Reload_priv, Shutdown_priv, Process_priv, File_priv, Grant_priv, References_priv,
                Index_priv, Alter_priv, Show_db_priv, Super_priv, Create_tmp_table_priv,
                Lock_tables_priv, Execute_priv, Repl_slave_priv, Repl_client_priv, Create_view_priv,
                Show_view_priv, Create_routine_priv, Alter_routine_priv, Create_user_priv,
                Event_priv, Trigger_priv, Create_tablespace_priv
            FROM mysql.user
            WHERE user = '$user' AND host = '$TEMPLATE_HOST';
            " 2>&1

            if [ $? -eq 0 ]; then
                echo "    ✅ Wildcard user created via table insertion!"
            else
                echo "    ❌ Table insertion failed, trying CREATE USER method..."

                # Fallback: Try CREATE USER methods
                if [ "$AUTH_PLUGIN" = "mysql_native_password" ]; then
                    echo "    📝 Trying CREATE USER with native password..."
                    mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$user'@'%' IDENTIFIED BY PASSWORD '$PASSWORD_HASH';" 2>&1
                else
                    echo "    📝 Trying CREATE USER with plugin $AUTH_PLUGIN..."
                    mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$user'@'%' IDENTIFIED WITH $AUTH_PLUGIN AS '$PASSWORD_HASH';" 2>&1
                fi

                if [ $? -ne 0 ]; then
                    echo "      ❌ All methods failed - wildcard user may not be created correctly"
                else
                    echo "      ✅ CREATE USER method succeeded!"
                fi
            fi

            # Grant database permissions
            echo "  📊 Granting database permissions..."
            DATABASES=$(mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -N -e "SELECT DISTINCT Db FROM mysql.db WHERE User = '$user' AND Db != '';" 2>/dev/null)

            for db in $DATABASES; do
                if [ -n "$db" ] && [ "$db" != "Db" ]; then
                    echo "    📂 Database: $db"
                    mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$user'@'%';" 2>/dev/null
                fi
            done
        fi
    else
        echo "  ✅ Wildcard user already exists with password"
    fi
done

echo ""
echo "🔄 Flushing privileges..."
mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" 2>/dev/null

echo ""
echo "📊 Final check:"
mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "
SELECT
    user,
    host,
    CASE WHEN host = '%' THEN '✅ WILDCARD' ELSE '📍 SPECIFIC' END as type,
    plugin,
    CASE
        WHEN authentication_string = '' OR authentication_string IS NULL THEN '❌ NO PASSWORD'
        ELSE '✅ HAS PASSWORD'
    END as status,
    CONCAT(LEFT(authentication_string, 20), '...') as password_preview
FROM mysql.user
WHERE user LIKE '\\_%' AND user != ''
ORDER BY user, host;
" 2>/dev/null

echo ""
echo "🧪 Testing connection with wildcard user..."
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
            echo "🔌 Testing $user with password from site config..."
            if mysql -h "$DB_HOST" -u "$user" -p"$DB_PASSWORD" -e "SELECT 1;" 2>/dev/null >/dev/null; then
                echo "  ✅ Connection successful!"
            else
                echo "  ❌ Connection failed - will try from any IP"
                mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -e "SELECT Host, User FROM mysql.user WHERE User = '$user';" 2>/dev/null
            fi
        fi
    fi
    break # Only test first user
done

echo "🎉 Direct wildcard creation completed!"
