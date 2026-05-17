#!/bin/bash

################################################################################
# sync-latest-backup.sh
# 
# Synchronizes the latest backup files for a given service from source to local host.
# Finds the latest timestamp and syncs only those files.
# This script should be run on the target host.
#
# Usage:
#   ./sync-latest-backup.sh [OPTIONS]
#
# Options:
#   --source-host <ssh-config>   SSH config name for source (e.g., ki.netcup)
#   --service <name>             Service name (e.g., stones, stonesdb)
#   --backup-dir <path>          Backup directory path (default: /var/dev/MIMS-Scenarios/_backups/)
#   --dry-run                    Show what would be synced without actual transfer
#   --help                       Show this help message
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BACKUP_DIR="/var/dev/MIMS-Scenarios/_backups/"
DRY_RUN=false
SOURCE_HOST=""
SERVICE=""

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to show help
show_help() {
    head -n 20 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-host)
            SOURCE_HOST="$2"
            shift 2
            ;;
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$SOURCE_HOST" ]; then
    print_error "Source host is required (use --source-host)"
    exit 1
fi

if [ -z "$SERVICE" ]; then
    print_error "Service name is required (use --service)"
    exit 1
fi

# Find latest timestamp on source host
print_info "Finding latest backup timestamp for service '${SERVICE}' on ${SOURCE_HOST}..."

LATEST_TIMESTAMP=$(ssh "${SOURCE_HOST}" "cd ${BACKUP_DIR} && ls -1 ${SERVICE}_[0-9]*_*.tar.gz 2>/dev/null | grep -oP '${SERVICE}_\K[0-9]{14}' | sort -r | head -n 1" || echo "")

if [ -z "$LATEST_TIMESTAMP" ]; then
    print_error "No backup files found for service '${SERVICE}' on ${SOURCE_HOST}"
    exit 1
fi

print_success "Latest timestamp found: ${LATEST_TIMESTAMP}"

# Count files with this timestamp
FILE_COUNT=$(ssh "${SOURCE_HOST}" "cd ${BACKUP_DIR} && ls -1 ${SERVICE}_${LATEST_TIMESTAMP}_*.tar.gz 2>/dev/null | wc -l" || echo "0")
print_info "Found ${FILE_COUNT} file(s) with timestamp ${LATEST_TIMESTAMP}"

# List files to be synced
echo ""
print_info "Files to be synced:"
FILES_TO_SYNC=$(ssh "${SOURCE_HOST}" "cd ${BACKUP_DIR} && ls -1 ${SERVICE}_${LATEST_TIMESTAMP}_*.tar.gz 2>/dev/null")
echo "$FILES_TO_SYNC" | while read -r file; do
    echo "  - $file"
done

# Build rsync command - sync specific files only
RSYNC_ARGS="-avzP"
if [ "$DRY_RUN" = "true" ]; then
    RSYNC_ARGS="$RSYNC_ARGS --dry-run"
fi

# Build files arguments for rsync
FILES_ARG=""
for file in $FILES_TO_SYNC; do
    FILES_ARG="$FILES_ARG ${SOURCE_HOST}:${BACKUP_DIR}${file}"
done

RSYNC_CMD="rsync $RSYNC_ARGS $FILES_ARG ${BACKUP_DIR}"

echo ""
echo "════════════════════════════════════════════════════════════════"
print_info "Rsync command:"
echo "  ${RSYNC_CMD}"
echo "════════════════════════════════════════════════════════════════"

if [ "$DRY_RUN" = "true" ]; then
    print_warning "DRY-RUN MODE - Executing with --dry-run"
fi

echo ""
print_info "Starting rsync..."

# Execute rsync locally (we are already on the target host)
if ${RSYNC_CMD}; then
    echo ""
    print_success "Sync completed successfully"
else
    echo ""
    print_error "Sync failed"
    exit 1
fi

echo ""
