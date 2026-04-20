#!/bin/bash

# Script to configure git to fetch all remote branches for Frappe apps
# Usage: ./fix-git-refs.sh apps/myapp

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <app-path>"
    echo "Example: $0 apps/myapp"
    exit 1
fi

APP_PATH="$1"

# Check if directory exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Directory $APP_PATH does not exist"
    exit 1
fi

# Check if it's a git repository
if [ ! -d "$APP_PATH/.git" ]; then
    echo "Error: $APP_PATH is not a git repository"
    exit 1
fi

echo "🔧 Configuring git to fetch all remote refs for $APP_PATH"

cd "$APP_PATH"

# Configure SSH to skip host key checking
echo "🔐 Configuring SSH to skip host key checking..."
git config core.sshCommand "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Get remote name (usually 'upstream' for Frappe apps)
REMOTE=$(git remote | head -n 1)
if [ -z "$REMOTE" ]; then
    echo "❌ No remote found"
    exit 1
fi
echo "🌐 Remote: $REMOTE"

# Show current fetch configuration
echo "📋 Current fetch refspec:"
git config --get-all "remote.$REMOTE.fetch" || echo "  (none configured)"

# Configure git to fetch all remote branches
echo "⚙️  Setting fetch refspec to get all remote branches..."
git config "remote.$REMOTE.fetch" "+refs/heads/*:refs/remotes/$REMOTE/*"

echo "✅ Updated fetch configuration"

# Now fetch to get all the refs
echo "📥 Fetching all remote branches..."
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git fetch "$REMOTE"

echo ""
echo "📋 Remote branches now available:"
BRANCH_COUNT=$(git branch -r | grep "^  $REMOTE/" | wc -l)
echo "  Count: $BRANCH_COUNT"

echo ""
echo "🎉 Git configured to fetch all remote branches for $APP_PATH"
echo "💡 Future git fetch commands will automatically get all remote branches"
