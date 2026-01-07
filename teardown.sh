#!/bin/bash

# Snowflake MCP for Claude Code - Teardown Script
# This script removes all configuration files created during setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================================================"
echo "🧹 SNOWFLAKE MCP FOR CLAUDE CODE - TEARDOWN"
echo -e "========================================================================${NC}"
echo ""

# Function to remove a file if it exists
remove_file() {
    local file=$1
    local description=$2

    if [ -f "$file" ]; then
        echo -e "${YELLOW}📍 Removing $description...${NC}"
        rm -f "$file"
        echo -e "${GREEN}✅ Removed: $file${NC}"
    else
        echo -e "${BLUE}ℹ️  Not found (already removed): $file${NC}"
    fi
}

# Remove .env file
remove_file "$SCRIPT_DIR/.env" ".env file (credentials)"

# Remove .mcp.json from home directory
remove_file "$HOME/.mcp.json" "Claude Code MCP configuration"

# Remove temporary OAuth code file
remove_file "/tmp/snowflake_oauth_code.txt" "temporary OAuth code file"

# Remove shell alias
echo ""
echo -e "${YELLOW}📍 Checking for shell alias...${NC}"

# Detect shell and config file
SHELL_CONFIG=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
else
    # Try to detect from $SHELL
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    fi
fi

if [ -n "$SHELL_CONFIG" ] && [ -f "$SHELL_CONFIG" ]; then
    # Check if alias exists
    if grep -q "alias refresh-mcp=" "$SHELL_CONFIG"; then
        echo -e "${YELLOW}Found alias in $SHELL_CONFIG${NC}"
        read -p "Do you want to remove the 'refresh-mcp' alias from your shell config? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Remove the alias and the comment line before it
            sed -i.bak '/# Snowflake MCP token refresh/,/alias refresh-mcp=/d' "$SHELL_CONFIG"
            # Remove backup file
            rm -f "${SHELL_CONFIG}.bak"
            echo -e "${GREEN}✅ Removed alias from $SHELL_CONFIG${NC}"
            echo -e "${YELLOW}⚠️  You may need to restart your terminal or run: source $SHELL_CONFIG${NC}"
        else
            echo -e "${BLUE}ℹ️  Kept alias in $SHELL_CONFIG${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  No alias found in $SHELL_CONFIG${NC}"
    fi
else
    echo -e "${BLUE}ℹ️  Could not detect shell config file${NC}"
fi

echo ""
echo -e "${BLUE}========================================================================"
echo "✨ TEARDOWN COMPLETE"
echo -e "========================================================================${NC}"
echo ""
echo "The following have been removed:"
echo "  - .env file (with OAuth credentials)"
echo "  - ~/.mcp.json (Claude Code configuration)"
echo "  - Temporary OAuth files"
echo "  - Shell alias (if you chose to remove it)"
echo ""
echo "To set up again, run:"
echo "  ./setup.sh init"
echo "  or start Claude Code and say: 'onboard me to query snowflake'"
echo ""
echo -e "${GREEN}You can now start fresh! 🎉${NC}"
