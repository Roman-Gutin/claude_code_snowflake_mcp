#!/bin/bash

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================================"
echo "🚀 SNOWFLAKE MCP FOR CLAUDE CODE - SETUP"
echo "========================================================================"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    echo ""

    local missing=0

    # Check for required commands
    if ! command_exists python3; then
        echo "❌ python3 is required but not installed"
        missing=1
    else
        echo "✅ python3 found"
    fi

    if ! command_exists curl; then
        echo "❌ curl is required but not installed"
        missing=1
    else
        echo "✅ curl found"
    fi

    if ! command_exists claude; then
        echo "⚠️  claude CLI not found - you'll need to install Claude Code"
        echo "   Visit: https://claude.ai/download"
    else
        echo "✅ claude CLI found"
    fi

    echo ""

    if [ $missing -eq 1 ]; then
        echo "❌ Please install missing prerequisites before continuing"
        exit 1
    fi
}

# Function to initialize .env file
init_env() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        echo "⚠️  .env file already exists"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Keeping existing .env file"
            return
        fi
    fi

    echo "📝 Creating .env file from template..."
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    echo "✅ Created .env file"
    echo ""
    echo "Please edit .env and fill in your values:"
    echo "  - SNOWFLAKE_ACCOUNT_IDENTIFIER"
    echo "  - OAUTH_CLIENT_ID"
    echo "  - OAUTH_CLIENT_SECRET"
    echo "  - MCP_DATABASE, MCP_SCHEMA, MCP_SERVER_NAME"
    echo ""
}

# Function to configure .mcp.json
configure_mcp() {
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        echo "❌ .env file not found. Run: ./setup.sh init"
        exit 1
    fi

    source "$PROJECT_ROOT/.env"

    if [ -z "$SNOWFLAKE_ACCOUNT_IDENTIFIER" ] || [ -z "$MCP_DATABASE" ] || [ -z "$MCP_SCHEMA" ] || [ -z "$MCP_SERVER_NAME" ]; then
        echo "❌ .env is not fully configured"
        echo "Please fill in all required values in .env"
        exit 1
    fi

    local MCP_CONFIG="$HOME/.mcp.json"
    local MCP_URL="https://${SNOWFLAKE_ACCOUNT_IDENTIFIER}.snowflakecomputing.com/api/v2/databases/${MCP_DATABASE}/schemas/${MCP_SCHEMA}/mcp-servers/${MCP_SERVER_NAME}"

    echo "📝 Configuring Claude Code MCP..."
    echo ""
    echo "MCP Server URL: $MCP_URL"
    echo "Config location: $MCP_CONFIG"
    echo ""

    # Create .mcp.json from template
    cat > "$MCP_CONFIG" << EOF
{
  "mcpServers": {
    "${MCP_FRIENDLY_NAME}": {
      "type": "http",
      "url": "${MCP_URL}",
      "headers": {
        "Authorization": "Bearer \${SNOWFLAKE_MCP_TOKEN}"
      }
    }
  }
}
EOF

    echo "✅ Created $MCP_CONFIG"
    echo ""
}

# Function to make scripts executable
make_executable() {
    echo "🔧 Making scripts executable..."
    chmod +x "$PROJECT_ROOT/scripts/oauth_flow.sh"
    chmod +x "$PROJECT_ROOT/scripts/refresh_token.sh"
    chmod +x "$PROJECT_ROOT/setup.sh"
    echo "✅ Scripts are now executable"
    echo ""
}

# Function to run OAuth flow
run_oauth() {
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        echo "❌ .env file not found. Run: ./setup.sh init"
        exit 1
    fi

    echo "🔐 Starting OAuth flow..."
    echo ""
    "$PROJECT_ROOT/scripts/oauth_flow.sh"
}

# Function to test connection
test_connection() {
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        echo "❌ .env file not found"
        exit 1
    fi

    source "$PROJECT_ROOT/.env"

    if [ -z "$OAUTH_REFRESH_TOKEN" ]; then
        echo "❌ No refresh token found. Run: ./setup.sh oauth"
        exit 1
    fi

    echo "🧪 Testing MCP connection..."
    echo ""

    # Get fresh token
    echo "📍 Getting access token..."
    ACCESS_TOKEN=$("$PROJECT_ROOT/scripts/refresh_token.sh")

    if [ -z "$ACCESS_TOKEN" ] || [[ "$ACCESS_TOKEN" == ERROR* ]]; then
        echo "❌ Failed to get access token"
        echo "$ACCESS_TOKEN"
        exit 1
    fi

    echo "✅ Got access token: ${ACCESS_TOKEN:0:40}..."
    echo ""

    # Test MCP endpoint
    echo "📍 Testing MCP endpoint..."
    MCP_URL="https://${SNOWFLAKE_ACCOUNT_IDENTIFIER}.snowflakecomputing.com/api/v2/databases/${MCP_DATABASE}/schemas/${MCP_SCHEMA}/mcp-servers/${MCP_SERVER_NAME}"

    RESPONSE=$(curl -s -X POST "$MCP_URL" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -d '{
        "jsonrpc":"2.0",
        "id":1,
        "method":"initialize",
        "params":{
          "protocolVersion":"2024-11-05",
          "capabilities":{},
          "clientInfo":{"name":"test","version":"1.0"}
        }
      }')

    if echo "$RESPONSE" | grep -q "serverInfo"; then
        echo "✅ MCP connection successful!"
        echo ""
        echo "$RESPONSE" | python3 -m json.tool
        echo ""
        echo "🎉 Everything is working!"
    else
        echo "❌ MCP connection failed"
        echo ""
        echo "$RESPONSE" | python3 -m json.tool
        exit 1
    fi
}

# Function to show usage instructions
show_usage() {
    echo "📚 Usage Instructions"
    echo ""
    echo "Daily usage:"
    echo "  export SNOWFLAKE_MCP_TOKEN=\$(./scripts/refresh_token.sh)"
    echo "  claude"
    echo ""
    echo "Or add to your ~/.zshrc or ~/.bashrc:"
    echo "  alias refresh-mcp='export SNOWFLAKE_MCP_TOKEN=\$(${PROJECT_ROOT}/scripts/refresh_token.sh)'"
    echo ""
    echo "Then use:"
    echo "  refresh-mcp"
    echo "  claude"
    echo ""
}

# Main menu
case "${1:-}" in
    init)
        check_prerequisites
        init_env
        make_executable
        ;;
    configure)
        make_executable
        configure_mcp
        ;;
    oauth)
        make_executable
        run_oauth
        ;;
    test)
        test_connection
        ;;
    all)
        check_prerequisites
        init_env
        echo "⚠️  Please edit .env file with your Snowflake credentials before continuing"
        echo "Then run: ./setup.sh oauth"
        ;;
    *)
        echo "Usage: ./setup.sh [command]"
        echo ""
        echo "Commands:"
        echo "  init        - Create .env file from template"
        echo "  configure   - Generate .mcp.json for Claude Code"
        echo "  oauth       - Run OAuth authorization flow"
        echo "  test        - Test MCP connection"
        echo "  all         - Run full setup (init only, then manual config needed)"
        echo ""
        echo "Quick start:"
        echo "  1. ./setup.sh init"
        echo "  2. Edit .env with your credentials"
        echo "  3. ./setup.sh oauth"
        echo "  4. ./setup.sh configure"
        echo "  5. ./setup.sh test"
        echo ""
        exit 1
        ;;
esac
