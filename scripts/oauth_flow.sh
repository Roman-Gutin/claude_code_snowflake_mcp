#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo "❌ ERROR: .env file not found!"
    echo "Please copy .env.example to .env and fill in your values:"
    echo "  cp .env.example .env"
    exit 1
fi

# Validate required variables
if [ -z "$SNOWFLAKE_ACCOUNT_IDENTIFIER" ] || [ -z "$OAUTH_CLIENT_ID" ] || [ -z "$OAUTH_CLIENT_SECRET" ]; then
    echo "❌ ERROR: Missing required environment variables!"
    echo "Please configure .env with:"
    echo "  - SNOWFLAKE_ACCOUNT_IDENTIFIER"
    echo "  - OAUTH_CLIENT_ID"
    echo "  - OAUTH_CLIENT_SECRET"
    exit 1
fi

echo "========================================================================"
echo "🔐 SNOWFLAKE MCP OAUTH AUTHORIZATION"
echo "========================================================================"
echo ""
echo "Account: $SNOWFLAKE_ACCOUNT_IDENTIFIER"
echo "Redirect URI: $OAUTH_REDIRECT_URI"
echo ""

# Start local callback server
echo "📍 Starting local callback server on port 3000..."
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
            html = """
                <html>
                <head>
                    <style>
                        body {
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                            max-width: 600px;
                            margin: 100px auto;
                            padding: 40px;
                            text-align: center;
                            background: #f5f5f5;
                        }
                        .success-box {
                            background: white;
                            padding: 40px;
                            border-radius: 10px;
                            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                        }
                        h1 { color: #28a745; }
                    </style>
                </head>
                <body>
                    <div class="success-box">
                        <h1>Authorization Successful!</h1>
                        <p>You can close this window and return to your terminal.</p>
                        <p style="color: #666; font-size: 14px; margin-top: 30px;">
                            The authorization code has been captured.<br>
                            The terminal will now exchange it for tokens.
                        </p>
                    </div>
                </body>
                </html>
            """
            self.wfile.write(html.encode())
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
AUTH_URL="https://${SNOWFLAKE_ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/authorize"
PARAMS="client_id=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${OAUTH_CLIENT_ID}'))")&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${OAUTH_REDIRECT_URI}'))")&response_type=code"

FULL_URL="${AUTH_URL}?${PARAMS}"

echo "📍 Opening browser for authentication..."
echo ""

# Try different commands based on OS
if command -v open &> /dev/null; then
    open "${FULL_URL}"  # macOS
elif command -v xdg-open &> /dev/null; then
    xdg-open "${FULL_URL}"  # Linux
elif command -v start &> /dev/null; then
    start "${FULL_URL}"  # Windows
else
    echo "⚠️  Could not open browser automatically."
    echo "Please open this URL manually:"
    echo "${FULL_URL}"
fi

# Wait for authorization code
echo "⏳ Waiting for authorization... (timeout in 120 seconds)"
echo ""

TIMEOUT=120
START_TIME=$(date +%s)

while [ ! -f /tmp/snowflake_oauth_code.txt ]; do
    sleep 1
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ ERROR: Authorization timed out"
        kill $SERVER_PID 2>/dev/null
        exit 1
    fi
done

AUTH_CODE=$(cat /tmp/snowflake_oauth_code.txt)
rm /tmp/snowflake_oauth_code.txt

# Stop callback server
kill $SERVER_PID 2>/dev/null

echo "✅ Authorization code received!"
echo ""
echo "📍 Exchanging code for tokens..."

# Exchange code for tokens
TOKEN_RESPONSE=$(curl -s -X POST \
  "https://${SNOWFLAKE_ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/token-request" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode "code=${AUTH_CODE}" \
  --data-urlencode "redirect_uri=${OAUTH_REDIRECT_URI}" \
  --data-urlencode "client_id=${OAUTH_CLIENT_ID}" \
  --data-urlencode "client_secret=${OAUTH_CLIENT_SECRET}")

# Check if successful
if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Tokens received successfully!"
    echo ""

    # Extract refresh token
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('refresh_token', ''))")

    if [ -n "$REFRESH_TOKEN" ]; then
        echo "📝 Updating .env with refresh token..."

        # Update .env file with refresh token
        if grep -q "^OAUTH_REFRESH_TOKEN=" "$PROJECT_ROOT/.env"; then
            # Replace existing line
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^OAUTH_REFRESH_TOKEN=.*|OAUTH_REFRESH_TOKEN=${REFRESH_TOKEN}|" "$PROJECT_ROOT/.env"
            else
                sed -i "s|^OAUTH_REFRESH_TOKEN=.*|OAUTH_REFRESH_TOKEN=${REFRESH_TOKEN}|" "$PROJECT_ROOT/.env"
            fi
        else
            # Append if not exists
            echo "OAUTH_REFRESH_TOKEN=${REFRESH_TOKEN}" >> "$PROJECT_ROOT/.env"
        fi

        echo "✅ Refresh token saved to .env"
    fi

    echo ""
    echo "========================================================================"
    echo "🎉 OAUTH SETUP COMPLETE!"
    echo "========================================================================"
    echo ""
    echo "Token details:"
    echo "$TOKEN_RESPONSE" | python3 -m json.tool
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./scripts/refresh_token.sh"
    echo "  2. Run: ./setup.sh configure"
    echo "  3. Test: export SNOWFLAKE_MCP_TOKEN=\$(./scripts/refresh_token.sh) && claude mcp list"
    echo ""
else
    echo "❌ ERROR: Token exchange failed"
    echo "$TOKEN_RESPONSE" | python3 -m json.tool
    exit 1
fi
