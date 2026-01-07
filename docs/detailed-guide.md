# Snowflake MCP Server Setup Guide for Claude Code

This guide walks through setting up a Snowflake-managed MCP (Model Context Protocol) server to work with Claude Code using OAuth authentication.

## Prerequisites

- Snowflake account with appropriate permissions
- Claude Code CLI installed
- Access to create MCP servers and OAuth integrations in Snowflake
- A Cortex Search Service already configured in Snowflake

## Overview

Setting up a Snowflake MCP server with Claude Code involves:
1. Creating an OAuth security integration in Snowflake
2. Creating the MCP server in Snowflake
3. Obtaining OAuth credentials
4. Performing OAuth authorization flow
5. Configuring Claude Code with the correct endpoint and token
6. Managing token refresh

## Step 1: Create OAuth Security Integration in Snowflake

Run this SQL in your Snowflake console:

```sql
CREATE SECURITY INTEGRATION claude_code_mcp_oauth
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://127.0.0.1:3000/oauth/callback'
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE;
```

**Important:** The redirect URI must be exactly `http://127.0.0.1:3000/oauth/callback` for the local OAuth flow.

## Step 2: Get OAuth Client Credentials

Retrieve your OAuth client credentials:

```sql
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_CODE_MCP_OAUTH');
```

This returns a JSON object with:
- `OAUTH_CLIENT_ID`
- `OAUTH_CLIENT_SECRET`
- `OAUTH_CLIENT_SECRET_2`

**Save these credentials** - you'll need them for the OAuth flow.

## Step 3: Create Your MCP Server in Snowflake

Create the MCP server pointing to your Cortex Search Service:

```sql
USE DATABASE your_database;
USE SCHEMA your_schema;

CREATE OR REPLACE MCP SERVER your_mcp_server_name
  FROM SPECIFICATION $
    tools:
      - name: "call-search"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "YOUR_DATABASE.YOUR_SCHEMA.YOUR_CORTEX_SEARCH_SERVICE"
        description: "Description of your search"
        title: "Search Title" $;
```

**Critical:** The identifier must match the exact name of your Cortex Search Service. Use fully qualified names (DATABASE.SCHEMA.SERVICE_NAME) in UPPERCASE.

To verify your Cortex Search Service exists:
```sql
SHOW CORTEX SEARCH SERVICES IN DATABASE your_database;
```

## Step 4: Understand the MCP Endpoint URL Pattern

Snowflake MCP servers use this REST API endpoint pattern:

```
https://<account_identifier>.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

**Example:**
```
https://MYORG-MYACCOUNT.snowflakecomputing.com/api/v2/databases/AICOLLEGE/schemas/PUBLIC/mcp-servers/gong_mcp
```

**Note:** This is different from the Cortex Search Service endpoint pattern. The MCP server has its own dedicated endpoint.

## Step 5: Perform OAuth Authorization Flow

### 5.1 Create OAuth Helper Script

Save this as `snowflake_oauth_flow.sh`:

```bash
#!/bin/bash

# REPLACE THESE WITH YOUR VALUES
CLIENT_ID="YOUR_CLIENT_ID_HERE"
CLIENT_SECRET="YOUR_CLIENT_SECRET_HERE"
ACCOUNT_IDENTIFIER="YOUR_ACCOUNT_IDENTIFIER"  # e.g., ORGNAME-ACCOUNTNAME
REDIRECT_URI="http://127.0.0.1:3000/oauth/callback"

# Start local callback server
python3 << 'EOF' &
import http.server
import socketserver
from urllib.parse import urlparse, parse_qs
import sys

PORT = 3000

class OAuthCallbackHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        params = parse_qs(parsed_path.query)

        if 'code' in params:
            auth_code = params['code'][0]

            with open('/tmp/snowflake_oauth_code.txt', 'w') as f:
                f.write(auth_code)

            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'''
                <html>
                <body style="font-family: Arial; padding: 50px; text-align: center;">
                    <h1 style="color: green;">Authorization Successful!</h1>
                    <p>You can close this window and return to your terminal.</p>
                </body>
                </html>
            ''')
            print(f"Authorization code received", file=sys.stderr)
        else:
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            error = params.get('error', ['Unknown'])[0]
            self.wfile.write(f'<html><body><h1>Error</h1><p>{error}</p></body></html>'.encode())

    def log_message(self, format, *args):
        pass

print(f"OAuth callback server started on http://127.0.0.1:{PORT}", file=sys.stderr)

with socketserver.TCPServer(("127.0.0.1", PORT), OAuthCallbackHandler) as httpd:
    httpd.serve_forever()
EOF

SERVER_PID=$!
sleep 2

# Build authorization URL
AUTH_URL="https://${ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/authorize"
PARAMS="client_id=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CLIENT_ID}'))")&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REDIRECT_URI}'))")&response_type=code"

FULL_URL="${AUTH_URL}?${PARAMS}"

echo "Opening authorization URL in browser..."
echo "${FULL_URL}"
open "${FULL_URL}"  # Use 'xdg-open' on Linux, 'start' on Windows

# Wait for authorization code
echo "Waiting for authorization..."
for i in {1..60}; do
  if [ -f /tmp/snowflake_oauth_code.txt ]; then
    AUTH_CODE=$(cat /tmp/snowflake_oauth_code.txt)
    echo "✓ Authorization code received!"
    break
  fi
  sleep 1
done

# Stop callback server
kill $SERVER_PID 2>/dev/null

if [ -z "$AUTH_CODE" ]; then
  echo "ERROR: Authorization timed out"
  exit 1
fi

# Exchange code for token
echo "Exchanging authorization code for access token..."

curl -s -X POST \
  "https://${ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/token-request" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode "code=${AUTH_CODE}" \
  --data-urlencode "redirect_uri=${REDIRECT_URI}" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" | python3 -m json.tool

echo ""
echo "✓ Save the access_token and refresh_token from above!"
```

### 5.2 Run the OAuth Flow

```bash
chmod +x snowflake_oauth_flow.sh
./snowflake_oauth_flow.sh
```

This will:
1. Start a local callback server on port 3000
2. Open your browser to Snowflake's OAuth authorization page
3. Capture the authorization code
4. Exchange it for access and refresh tokens

**Save the output** - you'll need both the `access_token` and `refresh_token`.

## Step 6: Configure Claude Code

### 6.1 Create or Update `.mcp.json`

Create/edit `~/.mcp.json` (for user-level config) or `./.mcp.json` (for project-level config):

```json
{
  "mcpServers": {
    "your_mcp_server_name": {
      "type": "http",
      "url": "https://YOUR_ACCOUNT.snowflakecomputing.com/api/v2/databases/YOUR_DB/schemas/YOUR_SCHEMA/mcp-servers/YOUR_MCP_SERVER",
      "headers": {
        "Authorization": "Bearer ${SNOWFLAKE_MCP_TOKEN}"
      }
    }
  }
}
```

**Replace:**
- `your_mcp_server_name`: A friendly name for Claude Code
- `YOUR_ACCOUNT`: Your Snowflake account identifier
- `YOUR_DB`: Your database name
- `YOUR_SCHEMA`: Your schema name
- `YOUR_MCP_SERVER`: Your MCP server name (from Step 3)

**Note:** We use `${SNOWFLAKE_MCP_TOKEN}` as an environment variable placeholder instead of hardcoding the token.

### 6.2 Verify Configuration

```bash
claude mcp list
```

You should see your MCP server listed. It may show as "Failed to connect" until you set the token.

## Step 7: Create Token Refresh Script

Create a helper script at `~/refresh_snowflake_mcp_token.sh`:

```bash
#!/bin/bash

# REPLACE THESE WITH YOUR VALUES
CLIENT_ID="YOUR_CLIENT_ID"
CLIENT_SECRET="YOUR_CLIENT_SECRET"
REFRESH_TOKEN="YOUR_REFRESH_TOKEN_FROM_STEP_5"
ACCOUNT_IDENTIFIER="YOUR_ACCOUNT_IDENTIFIER"

curl -s -X POST \
  "https://${ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/token-request" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=refresh_token' \
  --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('access_token', 'ERROR: ' + str(data)))"
```

Make it executable:
```bash
chmod +x ~/refresh_snowflake_mcp_token.sh
```

## Step 8: Using the MCP Server

### Start Claude Code with Token

**Option 1: Set token before starting:**
```bash
export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)
claude
```

**Option 2: Add to shell profile:**

Add to `~/.zshrc` or `~/.bashrc`:
```bash
# Function to refresh Snowflake MCP token
refresh_snowflake_token() {
  export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)
  echo "✓ Snowflake MCP token refreshed"
}

# Optionally auto-refresh on shell start
# refresh_snowflake_token
```

Then run `source ~/.zshrc` and use:
```bash
refresh_snowflake_token
claude
```

### Test the Connection

Once in Claude Code, you can verify the MCP server is working by asking Claude to use it:

```
Can you search for phone calls mentioning [your search term]?
```

Claude will use the MCP server's tools to query your Cortex Search Service.

## Step 9: Testing with curl

You can test the MCP endpoint directly:

```bash
# Set token
ACCESS_TOKEN=$(~/refresh_snowflake_mcp_token.sh)

# Test initialize
curl -s -X POST \
  "https://YOUR_ACCOUNT.snowflakecomputing.com/api/v2/databases/YOUR_DB/schemas/YOUR_SCHEMA/mcp-servers/YOUR_MCP_SERVER" \
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
  }' | python3 -m json.tool

# List available tools
curl -s -X POST \
  "https://YOUR_ACCOUNT.snowflakecomputing.com/api/v2/databases/YOUR_DB/schemas/YOUR_SCHEMA/mcp-servers/YOUR_MCP_SERVER" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/list",
    "params":{}
  }' | python3 -m json.tool

# Call a tool
curl -s -X POST \
  "https://YOUR_ACCOUNT.snowflakecomputing.com/api/v2/databases/YOUR_DB/schemas/YOUR_SCHEMA/mcp-servers/YOUR_MCP_SERVER" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"call-search",
      "arguments":{
        "query":"your search query",
        "limit":10
      }
    }
  }' | python3 -m json.tool
```

## Troubleshooting

### Issue: 404 Not Found

**Problem:** The MCP endpoint returns 404.

**Solution:** Verify you're using the correct endpoint pattern:
```
/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<SERVER_NAME>
```

Not:
- `/api/v2/cortex/mcp/<SERVER_NAME>` ❌
- `/api/mcp/<SERVER_NAME>` ❌
- `/mcp/<SERVER_NAME>` ❌

### Issue: OAuth Token Expired

**Problem:** Error message: `OAuth access token expired`

**Solution:** Tokens expire every 10 minutes. Refresh the token:
```bash
export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)
```

### Issue: Cortex Search Service Not Found

**Problem:** Error: `Cortex Search Service ... does not exist or access is not authorized`

**Solutions:**
1. Verify the Cortex Search Service exists:
   ```sql
   SHOW CORTEX SEARCH SERVICES IN DATABASE your_database;
   ```

2. Check the identifier in your MCP server spec matches exactly (case-sensitive):
   ```sql
   DESCRIBE MCP SERVER your_mcp_server;
   ```

3. Grant permissions to the role used by OAuth:
   ```sql
   GRANT USAGE ON CORTEX SEARCH SERVICE your_db.your_schema.your_service TO ROLE your_role;
   ```

4. Check which role your OAuth session is using:
   - Look at the `scope` field in the OAuth token response
   - Example: `"scope": "session:role:AICOLLEGE"` means the AICOLLEGE role needs permissions

### Issue: Connection Fails in Claude Code

**Problem:** `claude mcp list` shows "Failed to connect"

**Solutions:**
1. Verify the token environment variable is set:
   ```bash
   echo $SNOWFLAKE_MCP_TOKEN
   ```

2. Test the endpoint manually with curl (see Step 9)

3. Check the `.mcp.json` syntax is valid JSON

4. Ensure you started Claude Code after setting the environment variable

### Issue: Authorization Code Not Captured

**Problem:** OAuth flow times out waiting for code.

**Solutions:**
1. Manually complete the OAuth flow in browser
2. Check if port 3000 is already in use: `lsof -i :3000`
3. Ensure the redirect URI in Snowflake matches exactly: `http://127.0.0.1:3000/oauth/callback`

## Best Practices

1. **Token Management:**
   - Access tokens expire after 10 minutes
   - Refresh tokens are valid for ~90 days
   - Always use the refresh token to get new access tokens
   - Store refresh tokens securely (not in version control)

2. **Security:**
   - Never commit OAuth credentials to version control
   - Use environment variables for sensitive values
   - Consider using `.env` files with proper `.gitignore` entries
   - For team sharing, use project-scoped MCP configs with placeholder env vars

3. **Permissions:**
   - Grant least-privilege access to MCP tools
   - Use dedicated roles for MCP access
   - Audit role permissions regularly

4. **Naming Conventions:**
   - Use fully qualified identifiers (DATABASE.SCHEMA.OBJECT)
   - Keep names in UPPERCASE for consistency with Snowflake
   - Use descriptive names for MCP servers and tools

## Example: Complete Working Configuration

Here's a real example (with sanitized values):

**Snowflake Setup:**
```sql
-- Database and schema
USE DATABASE AICOLLEGE;
USE SCHEMA PUBLIC;

-- OAuth integration
CREATE SECURITY INTEGRATION claude_code_mcp_oauth
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://127.0.0.1:3000/oauth/callback'
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE;

-- MCP Server
CREATE OR REPLACE MCP SERVER gong_mcp
  FROM SPECIFICATION $
    tools:
      - name: "call-search"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "AICOLLEGE.PUBLIC.GONG_CALLS_SEARCH_ENRICHED"
        description: "cortex search for gong calls"
        title: "Gong Search" $;
```

**Claude Code Configuration (`~/.mcp.json`):**
```json
{
  "mcpServers": {
    "gong_mcp": {
      "type": "http",
      "url": "https://YOUR_ACCOUNT.snowflakecomputing.com/api/v2/databases/YOUR_DATABASE/schemas/YOUR_SCHEMA/mcp-servers/YOUR_MCP_SERVER",
      "headers": {
        "Authorization": "Bearer ${SNOWFLAKE_MCP_TOKEN}"
      }
    }
  }
}
```

**Usage:**
```bash
# Refresh token
export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)

# Start Claude Code
claude

# In Claude Code:
# "Can you search for phone calls mentioning databricks?"
```

## Additional Resources

- [Snowflake MCP Server Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)
- [Claude Code MCP Documentation](https://code.claude.com/docs/en/mcp.md)

## Summary

This guide walked through the complete process of setting up a Snowflake-managed MCP server with Claude Code, including:

1. Creating OAuth security integration in Snowflake
2. Creating and configuring the MCP server
3. Finding the correct REST API endpoint pattern
4. Performing OAuth authorization flow
5. Configuring Claude Code with proper authentication
6. Managing token refresh
7. Testing and troubleshooting

The key insights that required iteration:
- The MCP endpoint uses `/api/v2/databases/.../mcp-servers/...` (not `/api/v2/cortex/mcp/...`)
- Cortex Search Service identifiers must match exactly (case-sensitive)
- OAuth tokens expire quickly and need refresh token management
- Environment variable expansion in `.mcp.json` enables secure token management
