#!/bin/bash

# Set the script to exit immediately if any command fails
set -e

pushd $(dirname "$0") > /dev/null
cwd=$(pwd)
popd > /dev/null

# Check arg #1
if [ -z "$3" ]; then
  echo "Usage: $0 <src_site> <dest_site> <db_file>"
  echo
  echo "files and private files tar will also be converted"
  exit 1
fi
SRC_SITE=$1
DEST_SITE=$2
DB_FILE=$3

# Check if the db file exist
if [ ! -f "$DB_FILE" ]; then
  echo "Error: $DB_FILE does not exist."
  exit 1
fi

# Unzip the database file
if [[ "$DB_FILE" == *.sql.gz ]]; then
    if [ -f "${DB_FILE%.gz}" ]; then
        echo "Skip: ${DB_FILE%.gz} already exists."
    else
        echo "Unzipping $DB_FILE"
        gunzip -k "$DB_FILE"
    fi
    DB_FILE="${DB_FILE%.gz}"
fi

# Other variables
# Assuming the database file is named like "site1-database.sql"
BASE="${DB_FILE%%-database.sql}"
FILES_TAR="${BASE}-files.tar"
PRIVATE_FILES_TAR="${BASE}-private-files.tar"

# Extract DATETAG from DB_FILE (e.g., 20250401_200011 from 20250401_200011-test-ueag-jena_frappe_cloud-database.sql)
DATETAG=$(basename "$BASE" | cut -d'-' -f1 | cut -d'_' -f1,2)
NEWBASE="$(dirname $BASE)/${DATETAG}-${DEST_SITE//./_}"

# Print variables
echo "SRC_SITE: $SRC_SITE"
echo "DEST_SITE: $DEST_SITE"
#echo "DB_FILE: $DB_FILE"
#echo "FILES_TAR: $FILES_TAR"
#echo "PRIVATE_FILES_TAR: $PRIVATE_FILES_TAR"
#echo "BASE    : $BASE"
#echo "NEWBASE : $NEWBASE"

# Convert the database file
echo "Converting db  file: $DB_FILE"
cat "$DB_FILE" | sed "s/$SRC_SITE/$DEST_SITE/g" > "${NEWBASE}-database.sql"

convert_tar() {
    local src_tar="$1"
    local src_site="$2"
    local dest_site="$3"
    local dest_tar="$4"

    echo "Converting tar file: $src_tar"
    if [ -f "$src_tar" ]; then
        mkdir -p _tmp
        cp "$src_tar" _tmp/
        pushd _tmp > /dev/null
        tar -xf "$src_tar"
        rm "$src_tar"
        mv "$src_site" "$dest_site"
        tar -cf "$dest_tar" "$dest_site"
        rm -rf "$dest_site"
        popd > /dev/null
        mv _tmp/"$dest_tar" .
        rm -rf _tmp
    else
        echo "Warning: $src_tar does not exist. Skipping files tar conversion."
    fi
}

convert_tar "$FILES_TAR" "$SRC_SITE" "$DEST_SITE" "${NEWBASE}-files.tar"
convert_tar "$PRIVATE_FILES_TAR" "$SRC_SITE" "$DEST_SITE" "${NEWBASE}-private-files.tar"

# docker exec -it erpnext-test_erpnext_frontend_container /bin/bash
# ln -s /var/dev/MIMS-Scenarios/backups b
# bench --site test.schmidtundtoechter.com restore ./b/database.sql
# rsync -avzP /var/dev/MIMS-Scenarios/backups/test-ueag-jena.frappe.cloud/ ./sites/test.schmidtundtoechter.com/
# server restart
