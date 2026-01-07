# Organization-Wide Snowflake MCP Setup with SSO

This guide covers deploying Snowflake MCP access for multiple users in an organization that uses SSO.

## Architecture Overview

```
┌──────────────┐
│   User 1     │───┐
│ (SSO Auth)   │   │
└──────────────┘   │
                   │     ┌─────────────────┐      ┌──────────────────┐
┌──────────────┐   │     │  Token Service  │      │  Snowflake MCP   │
│   User 2     │───┼────→│  (Vault/Redis)  │─────→│     Server       │
│ (SSO Auth)   │   │     │  Auto-refresh   │      │                  │
└──────────────┘   │     └─────────────────┘      └──────────────────┘
                   │              ↓
┌──────────────┐   │         [Audit Log]
│   User 10    │───┘         Shows user
│ (SSO Auth)   │             identity
└──────────────┘
```

## Components

1. **Snowflake OAuth Integration** - Uses existing SSO
2. **Token Service** - Centralized token storage and refresh
3. **User Setup** - One-time OAuth flow per user
4. **Claude Code Config** - Fetches token from service

## Step 1: Snowflake Setup

### 1.1 Create OAuth Integration with SSO

```sql
-- This integration will use your existing Snowflake SSO configuration
CREATE OR REPLACE SECURITY INTEGRATION claude_code_mcp_oauth
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://127.0.0.1:3000/oauth/callback'
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 7776000;  -- 90 days

-- Get OAuth credentials (share with IT/Admin only)
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_CODE_MCP_OAUTH');
```

### 1.2 Create MCP Server

```sql
USE DATABASE AICOLLEGE;
USE SCHEMA PUBLIC;

CREATE OR REPLACE MCP SERVER gong_mcp
  FROM SPECIFICATION $
    tools:
      - name: "call-search"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "AICOLLEGE.PUBLIC.GONG_CALLS_SEARCH_ENRICHED"
        description: "cortex search for gong calls"
        title: "Gong Search" $;
```

### 1.3 Grant Permissions to Users

```sql
-- Create role for MCP users
CREATE ROLE IF NOT EXISTS MCP_USERS;

-- Grant permissions
GRANT USAGE ON DATABASE AICOLLEGE TO ROLE MCP_USERS;
GRANT USAGE ON SCHEMA AICOLLEGE.PUBLIC TO ROLE MCP_USERS;
GRANT USAGE ON CORTEX SEARCH SERVICE AICOLLEGE.PUBLIC.GONG_CALLS_SEARCH_ENRICHED
  TO ROLE MCP_USERS;

-- Grant role to users (or their existing roles)
GRANT ROLE MCP_USERS TO ROLE YOUR_EXISTING_SSO_ROLE;
```

## Step 2: Token Service Setup

### Option A: Simple Shared Service (Recommended for Small Teams)

Deploy a token refresh service that all users connect to:

**File: `token_service.py`**

```python
#!/usr/bin/env python3
"""
Centralized token refresh service for Snowflake MCP
Manages tokens for multiple users with auto-refresh
"""

from flask import Flask, request, jsonify
import requests
import time
import json
import os
from threading import Thread, Lock
from datetime import datetime

app = Flask(__name__)

# In-memory token storage (use Redis/Vault for production)
user_tokens = {}
token_lock = Lock()

# Configuration
SNOWFLAKE_ACCOUNT = os.getenv('SNOWFLAKE_ACCOUNT', 'YOURORG-YOURACCOUNT')
CLIENT_ID = os.getenv('OAUTH_CLIENT_ID')
CLIENT_SECRET = os.getenv('OAUTH_CLIENT_SECRET')

def refresh_user_token(username, refresh_token):
    """Refresh a specific user's token"""
    try:
        response = requests.post(
            f'https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/oauth/token-request',
            data={
                'grant_type': 'refresh_token',
                'refresh_token': refresh_token,
                'client_id': CLIENT_ID,
                'client_secret': CLIENT_SECRET
            },
            headers={'Content-Type': 'application/x-www-form-urlencoded'}
        )

        if response.status_code == 200:
            data = response.json()

            with token_lock:
                user_tokens[username] = {
                    'access_token': data['access_token'],
                    'refresh_token': refresh_token,
                    'expires_at': time.time() + data['expires_in'] - 60,  # 1 min buffer
                    'last_refresh': datetime.now().isoformat()
                }

            print(f"[{datetime.now()}] Token refreshed for user: {username}")
            return True
        else:
            print(f"[{datetime.now()}] Token refresh failed for {username}: {response.text}")
            return False

    except Exception as e:
        print(f"[{datetime.now()}] Error refreshing token for {username}: {e}")
        return False

def auto_refresh_loop():
    """Background thread to auto-refresh tokens before expiry"""
    while True:
        try:
            current_time = time.time()

            with token_lock:
                users_to_refresh = [
                    (user, data['refresh_token'])
                    for user, data in user_tokens.items()
                    if current_time >= data['expires_at']
                ]

            for username, refresh_token in users_to_refresh:
                refresh_user_token(username, refresh_token)

        except Exception as e:
            print(f"[{datetime.now()}] Auto-refresh error: {e}")

        time.sleep(30)  # Check every 30 seconds

@app.route('/register', methods=['POST'])
def register_user():
    """
    Register a user's refresh token
    POST /register
    Body: {"username": "user@example.com", "refresh_token": "..."}
    """
    data = request.json
    username = data.get('username')
    refresh_token = data.get('refresh_token')

    if not username or not refresh_token:
        return jsonify({'error': 'Missing username or refresh_token'}), 400

    # Try to refresh immediately to validate
    if refresh_user_token(username, refresh_token):
        return jsonify({'message': 'User registered successfully', 'username': username})
    else:
        return jsonify({'error': 'Invalid refresh token'}), 400

@app.route('/token/<username>', methods=['GET'])
def get_token(username):
    """
    Get current access token for a user
    GET /token/user@example.com
    """
    with token_lock:
        if username not in user_tokens:
            return jsonify({'error': 'User not registered'}), 404

        user_data = user_tokens[username]

        # Check if token needs refresh
        if time.time() >= user_data['expires_at']:
            # Token expired, try to refresh
            if not refresh_user_token(username, user_data['refresh_token']):
                return jsonify({'error': 'Token expired and refresh failed'}), 401
            user_data = user_tokens[username]

        return jsonify({
            'access_token': user_data['access_token'],
            'expires_at': user_data['expires_at'],
            'last_refresh': user_data['last_refresh']
        })

@app.route('/users', methods=['GET'])
def list_users():
    """List all registered users"""
    with token_lock:
        return jsonify({
            'users': list(user_tokens.keys()),
            'count': len(user_tokens)
        })

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'users': len(user_tokens)})

if __name__ == '__main__':
    print(f"Starting Snowflake MCP Token Service...")
    print(f"Snowflake Account: {SNOWFLAKE_ACCOUNT}")

    # Start auto-refresh thread
    Thread(target=auto_refresh_loop, daemon=True).start()

    # Start Flask server
    app.run(host='0.0.0.0', port=8080)
```

**Deployment (Docker):**

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install flask requests

COPY token_service.py .

ENV FLASK_ENV=production

EXPOSE 8080

CMD ["python", "token_service.py"]
```

```bash
# Build and run
docker build -t snowflake-token-service .

docker run -d \
  -p 8080:8080 \
  -e SNOWFLAKE_ACCOUNT="YOURORG-YOURACCOUNT" \
  -e OAUTH_CLIENT_ID="your_client_id" \
  -e OAUTH_CLIENT_SECRET="your_client_secret" \
  --name snowflake-token-service \
  snowflake-token-service
```

## Step 3: User Onboarding

### 3.1 User Setup Script

Distribute this script to each user for one-time setup:

**File: `setup_mcp.sh`**

```bash
#!/bin/bash

# Configuration
SNOWFLAKE_ACCOUNT="YOURORG-YOURACCOUNT"
CLIENT_ID="your_client_id"
CLIENT_SECRET="your_client_secret"
TOKEN_SERVICE_URL="http://token-service.internal:8080"  # Your token service
REDIRECT_URI="http://127.0.0.1:3000/oauth/callback"

echo "==================================="
echo "Snowflake MCP Setup for Claude Code"
echo "==================================="
echo ""

# Get username
echo "Enter your email/username:"
read USERNAME

echo ""
echo "Starting OAuth flow..."
echo "This will open your browser for SSO authentication."
echo ""

# Start callback server
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
                    <p>You can close this window.</p>
                </body>
                </html>
            ''')

    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(("127.0.0.1", PORT), OAuthCallbackHandler) as httpd:
    httpd.serve_forever()
EOF

SERVER_PID=$!
sleep 2

# Build auth URL
python3 << EOF
import urllib.parse
import webbrowser

client_id = "${CLIENT_ID}"
redirect_uri = "${REDIRECT_URI}"
account = "${SNOWFLAKE_ACCOUNT}"

auth_url = f"https://{account}.snowflakecomputing.com/oauth/authorize"
params = urllib.parse.urlencode({
    "client_id": client_id,
    "redirect_uri": redirect_uri,
    "response_type": "code"
})

full_url = f"{auth_url}?{params}"
print("Opening browser...")
webbrowser.open(full_url)
EOF

# Wait for code
echo "Waiting for authorization..."
for i in {1..60}; do
  if [ -f /tmp/snowflake_oauth_code.txt ]; then
    AUTH_CODE=$(cat /tmp/snowflake_oauth_code.txt)
    rm /tmp/snowflake_oauth_code.txt
    break
  fi
  sleep 1
done

kill $SERVER_PID 2>/dev/null

if [ -z "$AUTH_CODE" ]; then
  echo "ERROR: Authorization timed out"
  exit 1
fi

echo "✓ Authorization successful"
echo ""
echo "Exchanging code for tokens..."

# Exchange for tokens
RESPONSE=$(curl -s -X POST \
  "https://${SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/oauth/token-request" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode "code=${AUTH_CODE}" \
  --data-urlencode "redirect_uri=${REDIRECT_URI}" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}")

# Extract refresh token
REFRESH_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['refresh_token'])")

if [ -z "$REFRESH_TOKEN" ]; then
  echo "ERROR: Failed to get refresh token"
  echo "$RESPONSE"
  exit 1
fi

echo "✓ Tokens received"
echo ""
echo "Registering with token service..."

# Register with token service
REGISTER_RESPONSE=$(curl -s -X POST \
  "${TOKEN_SERVICE_URL}/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\": \"${USERNAME}\", \"refresh_token\": \"${REFRESH_TOKEN}\"}")

echo "$REGISTER_RESPONSE" | python3 -m json.tool

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Add this to your ~/.zshrc or ~/.bashrc:"
echo ""
echo "   # Snowflake MCP Token"
echo "   export TOKEN_SERVICE_URL=\"${TOKEN_SERVICE_URL}\""
echo "   export MCP_USERNAME=\"${USERNAME}\""
echo "   alias refresh_mcp='export SNOWFLAKE_MCP_TOKEN=\$(curl -s \$TOKEN_SERVICE_URL/token/\$MCP_USERNAME | python3 -c \"import sys, json; print(json.load(sys.stdin)['"'"'access_token'"'"'])\")'"
echo ""
echo "2. Run: source ~/.zshrc"
echo "3. Before using Claude Code: refresh_mcp"
echo "4. Start Claude Code: claude"
```

### 3.2 User's `.mcp.json` Configuration

Each user creates `~/.mcp.json`:

```json
{
  "mcpServers": {
    "gong_mcp": {
      "type": "http",
      "url": "https://YOURORG-YOURACCOUNT.snowflakecomputing.com/api/v2/databases/AICOLLEGE/schemas/PUBLIC/mcp-servers/gong_mcp",
      "headers": {
        "Authorization": "Bearer ${SNOWFLAKE_MCP_TOKEN}"
      }
    }
  }
}
```

### 3.3 Daily Usage

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Snowflake MCP Configuration
export TOKEN_SERVICE_URL="http://token-service.internal:8080"
export MCP_USERNAME="your.email@company.com"

# Alias to refresh token
alias refresh_mcp='export SNOWFLAKE_MCP_TOKEN=$(curl -s $TOKEN_SERVICE_URL/token/$MCP_USERNAME | python3 -c "import sys, json; print(json.load(sys.stdin)[\"access_token\"])")'

# Optional: Auto-refresh on shell start
# refresh_mcp
```

**User workflow:**
```bash
# Refresh token (good for ~10 minutes)
refresh_mcp

# Start Claude Code
claude

# Ask Claude to query MCP
# "Can you search for phone calls mentioning databricks?"
```

## Step 4: Administration

### Token Service Management

**Check service health:**
```bash
curl http://token-service.internal:8080/health
```

**List registered users:**
```bash
curl http://token-service.internal:8080/users
```

**Manually register a user:**
```bash
curl -X POST http://token-service.internal:8080/register \
  -H 'Content-Type: application/json' \
  -d '{"username": "user@company.com", "refresh_token": "..."}'
```

### Monitoring

Add logging and monitoring to track:
- Token refresh frequency
- Failed refreshes
- User activity
- Service uptime

**Example with CloudWatch/Datadog:**
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/var/log/token-service.log'),
        logging.StreamHandler()
    ]
)
```

## Security Considerations

1. **Token Storage:**
   - Production: Use HashiCorp Vault, AWS Secrets Manager, or Azure Key Vault
   - Never store in plain text files
   - Encrypt at rest

2. **Network Security:**
   - Deploy token service behind VPN/firewall
   - Use HTTPS in production
   - Implement API authentication for token service

3. **Access Control:**
   - Limit who can register new users
   - Audit token access
   - Rotate OAuth credentials regularly

4. **Token Lifecycle:**
   - Monitor refresh token expiry (90 days)
   - Alert before expiry
   - Implement re-authentication flow

## Production Deployment

### Using Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snowflake-token-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: snowflake-token-service
  template:
    metadata:
      labels:
        app: snowflake-token-service
    spec:
      containers:
      - name: token-service
        image: your-registry/snowflake-token-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: SNOWFLAKE_ACCOUNT
          value: "YOURORG-YOURACCOUNT"
        - name: OAUTH_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: snowflake-oauth
              key: client-id
        - name: OAUTH_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: snowflake-oauth
              key: client-secret
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: snowflake-token-service
spec:
  selector:
    app: snowflake-token-service
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

### Using AWS ECS

```json
{
  "family": "snowflake-token-service",
  "containerDefinitions": [
    {
      "name": "token-service",
      "image": "your-registry/snowflake-token-service:latest",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "secrets": [
        {
          "name": "OAUTH_CLIENT_ID",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:snowflake/client-id"
        },
        {
          "name": "OAUTH_CLIENT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:snowflake/client-secret"
        }
      ],
      "environment": [
        {
          "name": "SNOWFLAKE_ACCOUNT",
          "value": "YOURORG-YOURACCOUNT"
        }
      ]
    }
  ]
}
```

## Troubleshooting

### User Can't Authenticate
- Check SSO configuration in Snowflake
- Verify OAuth integration is enabled
- Ensure user has correct role permissions

### Token Service Down
- Users can fall back to manual refresh:
  ```bash
  export SNOWFLAKE_MCP_TOKEN=$(~/manual_refresh_token.sh)
  ```

### Tokens Not Refreshing
- Check token service logs
- Verify refresh token hasn't expired (90 days)
- Test OAuth credentials manually

## Alternative: Snowflake Key Pair Authentication

For teams that prefer not to manage OAuth tokens, Snowflake supports key pair authentication:

```sql
-- Generate key pair (one-time)
-- openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
-- openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub

-- Add public key to user
ALTER USER mcp_user SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...';
```

However, this doesn't work with MCP's OAuth requirement, so OAuth is necessary.

## Summary

This architecture provides:
- ✅ SSO integration for user authentication
- ✅ Individual audit trails (queries show as specific users)
- ✅ Centralized token management
- ✅ Automatic token refresh
- ✅ Simple user experience
- ✅ Production-ready deployment options

Each user authenticates once with their SSO credentials, and the token service handles refresh automatically. Users just run `refresh_mcp` before using Claude Code.
