#!/bin/bash

################################################################################
# link-backup-files.sh
# 
# Creates symbolic links for backup files on a remote server.
# Example: stonesdb_20251023_035121_bench-data.tar.gz 
#       -> stonesdb-stage_20251023_035121_bench-data.tar.gz
#
# Usage:
#   ./link-backup-files.sh [OPTIONS]
#
# Options:
#   --remote <ssh-config>    SSH config name (e.g., ki.netcup)
#   --source <scenario>      Source scenario name (e.g., stonesdb)
#   --dest <scenario>        Destination scenario name (e.g., stonesdb-stage)
#   --backup-dir <path>      Backup directory path (default: /var/dev/MIMS-Scenarios/_backups)
#   --pattern <pattern>      Filter files by pattern (e.g., 20251023*)
#   --latest                 Also create links with 'latest' instead of timestamp
#   --dry-run                Show what would be done without creating links
#   --force                  Overwrite existing links
#   --help                   Show this help message
################################################################################

set -e

# Check if running in interactive shell
IS_INTERACTIVE=false
if [ -t 0 ] && [ -t 1 ]; then
    IS_INTERACTIVE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BACKUP_DIR="/var/dev/MIMS-Scenarios/_backups"
DRY_RUN=false
FORCE=false
CREATE_LATEST=false
REMOTE=""
SOURCE=""
DEST=""
PATTERN=""

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
    head -n 25 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --source)
            SOURCE="$2"
            shift 2
            ;;
        --dest)
            DEST="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --pattern)
            PATTERN="$2"
            shift 2
            ;;
        --latest)
            CREATE_LATEST=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
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

# Handle missing parameters
if [ -z "$REMOTE" ]; then
    if [ "$IS_INTERACTIVE" = "true" ]; then
        echo ""
        print_info "Enter SSH config name (e.g., ki.netcup):"
        read -r REMOTE
    fi
    if [ -z "$REMOTE" ]; then
        print_error "Remote SSH config is required (use --remote)"
        exit 1
    fi
fi

if [ -z "$SOURCE" ]; then
    if [ "$IS_INTERACTIVE" = "true" ]; then
        echo ""
        print_info "Enter source scenario name (e.g., stonesdb):"
        read -r SOURCE
    fi
    if [ -z "$SOURCE" ]; then
        print_error "Source scenario name is required (use --source)"
        exit 1
    fi
fi

if [ -z "$DEST" ]; then
    if [ "$IS_INTERACTIVE" = "true" ]; then
        echo ""
        print_info "Enter destination scenario name (e.g., stonesdb-stage):"
        read -r DEST
    fi
    if [ -z "$DEST" ]; then
        print_error "Destination scenario name is required (use --dest)"
        exit 1
    fi
fi

# Test SSH connection
echo ""
print_info "Testing SSH connection to ${REMOTE}..."
if ! ssh "$REMOTE" "echo 'Connection successful'" >/dev/null 2>&1; then
    print_error "Cannot connect to ${REMOTE}"
    exit 1
fi
print_success "Connected to ${REMOTE}"

# Check if backup directory exists
echo ""
print_info "Checking backup directory ${BACKUP_DIR}..."
if ! ssh "$REMOTE" "test -d ${BACKUP_DIR}"; then
    print_error "Backup directory ${BACKUP_DIR} does not exist on ${REMOTE}"
    exit 1
fi
print_success "Backup directory exists"

# Build search pattern
if [ -n "$PATTERN" ]; then
    SEARCH_PATTERN="${SOURCE}_${PATTERN}"
else
    SEARCH_PATTERN="${SOURCE}_*"
fi

# Get list of source files
echo ""
print_info "Searching for files matching pattern: ${SEARCH_PATTERN}"
# Use while read loop for compatibility with macOS/zsh
SOURCE_FILES=()
while IFS= read -r line; do
    [ -n "$line" ] && SOURCE_FILES+=("$line")
done < <(ssh "$REMOTE" "cd ${BACKUP_DIR} && ls -1 ${SEARCH_PATTERN} 2>/dev/null || true")

if [ ${#SOURCE_FILES[@]} -eq 0 ]; then
    print_warning "No files found matching pattern: ${SEARCH_PATTERN}"
    exit 0
fi

print_success "Found ${#SOURCE_FILES[@]} file(s)"

# Prepare link commands
declare -a LINK_COMMANDS
declare -a EXISTING_LINKS
LINKS_TO_CREATE=0
LATEST_TIMESTAMP=""

echo ""
print_info "Preparing link operations..."
echo ""

# First pass: find the latest timestamp if --latest is enabled
if [ "$CREATE_LATEST" = "true" ]; then
    for source_file in "${SOURCE_FILES[@]}"; do
        # Extract timestamp from filename (format: scenario_YYYYMMDDHHMMSS_...)
        if [[ $source_file =~ ${SOURCE}_([0-9]{14})_ ]]; then
            timestamp="${BASH_REMATCH[1]}"
            if [ -z "$LATEST_TIMESTAMP" ] || [ "$timestamp" \> "$LATEST_TIMESTAMP" ]; then
                LATEST_TIMESTAMP="$timestamp"
            fi
        fi
    done
    
    if [ -n "$LATEST_TIMESTAMP" ]; then
        print_info "Latest timestamp found: ${LATEST_TIMESTAMP}"
        echo ""
    fi
fi

for source_file in "${SOURCE_FILES[@]}"; do
    # Replace source scenario name with dest scenario name
    dest_file="${source_file/${SOURCE}_/${DEST}_}"
    
    # Check if destination already exists
    DEST_EXISTS=$(ssh "$REMOTE" "cd ${BACKUP_DIR} && test -e ${dest_file} && echo 'yes' || echo 'no'")
    
    if [ "$DEST_EXISTS" = "yes" ] && [ "$FORCE" = "false" ]; then
        print_warning "Skip: ${dest_file} (already exists)"
        EXISTING_LINKS+=("$dest_file")
    else
        if [ "$DEST_EXISTS" = "yes" ]; then
            print_info "Overwrite: ${source_file} -> ${dest_file}"
        else
            print_info "Link: ${source_file} -> ${dest_file}"
        fi
        LINK_COMMANDS+=("cd ${BACKUP_DIR} && ln -sf ${source_file} ${dest_file}")
        LINKS_TO_CREATE=$((LINKS_TO_CREATE + 1))
    fi
    
    # If --latest is enabled and this file has the latest timestamp, create an additional "latest" link
    if [ "$CREATE_LATEST" = "true" ] && [[ $source_file =~ ${SOURCE}_${LATEST_TIMESTAMP}_ ]]; then
        # Create a "latest" version of the link
        latest_dest_file="${source_file/${SOURCE}_${LATEST_TIMESTAMP}_/${DEST}_latest_}"
        
        LATEST_EXISTS=$(ssh "$REMOTE" "cd ${BACKUP_DIR} && test -e ${latest_dest_file} && echo 'yes' || echo 'no'")
        
        if [ "$LATEST_EXISTS" = "yes" ] && [ "$FORCE" = "false" ]; then
            print_warning "Skip: ${latest_dest_file} (already exists)"
            EXISTING_LINKS+=("$latest_dest_file")
        else
            if [ "$LATEST_EXISTS" = "yes" ]; then
                print_info "Overwrite (latest): ${source_file} -> ${latest_dest_file}"
            else
                print_info "Link (latest): ${source_file} -> ${latest_dest_file}"
            fi
            LINK_COMMANDS+=("cd ${BACKUP_DIR} && ln -sf ${source_file} ${latest_dest_file}")
            LINKS_TO_CREATE=$((LINKS_TO_CREATE + 1))
        fi
    fi
done

# Summary before execution
echo ""
echo "════════════════════════════════════════════════════════════════"
print_info "Summary:"
echo "  Remote:       ${REMOTE}"
echo "  Backup dir:   ${BACKUP_DIR}"
echo "  Source:       ${SOURCE}"
echo "  Destination:  ${DEST}"
echo "  Pattern:      ${PATTERN:-*}"
echo "  Files found:  ${#SOURCE_FILES[@]}"
echo "  Links to create: ${LINKS_TO_CREATE}"
if [ "$CREATE_LATEST" = "true" ]; then
    echo "  Create latest links: yes (timestamp: ${LATEST_TIMESTAMP})"
fi
if [ ${#EXISTING_LINKS[@]} -gt 0 ]; then
    echo "  Already exist:   ${#EXISTING_LINKS[@]}"
fi
if [ "$DRY_RUN" = "true" ]; then
    print_warning "DRY-RUN MODE - No changes will be made"
fi
echo "════════════════════════════════════════════════════════════════"

if [ $LINKS_TO_CREATE -eq 0 ]; then
    echo ""
    print_success "Nothing to do. All links already exist."
    exit 0
fi

# Ask for confirmation if interactive and not in dry-run mode
if [ "$DRY_RUN" = "false" ] && [ "$IS_INTERACTIVE" = "true" ]; then
    echo ""
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled"
        exit 0
    fi
fi

# Execute link commands
if [ "$DRY_RUN" = "false" ]; then
    echo ""
    print_info "Creating symbolic links..."
    
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    
    for cmd in "${LINK_COMMANDS[@]}"; do
        if ssh "$REMOTE" "$cmd" 2>/dev/null; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    if [ $ERROR_COUNT -eq 0 ]; then
        print_success "Successfully created ${SUCCESS_COUNT} symbolic link(s)"
    else
        print_warning "Created ${SUCCESS_COUNT} link(s), ${ERROR_COUNT} error(s)"
    fi
    echo "════════════════════════════════════════════════════════════════"
else
    echo ""
    print_info "Dry-run completed. No changes were made."
fi

echo ""
