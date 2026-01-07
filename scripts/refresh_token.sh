#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo "ERROR: .env file not found!" >&2
    echo "Please run: cp .env.example .env and configure it" >&2
    exit 1
fi

# Validate required variables
if [ -z "$SNOWFLAKE_ACCOUNT_IDENTIFIER" ] || [ -z "$OAUTH_CLIENT_ID" ] || [ -z "$OAUTH_CLIENT_SECRET" ]; then
    echo "ERROR: Missing required environment variables in .env" >&2
    exit 1
fi

if [ -z "$OAUTH_REFRESH_TOKEN" ]; then
    echo "ERROR: OAUTH_REFRESH_TOKEN not set in .env" >&2
    echo "Please run: ./scripts/oauth_flow.sh first" >&2
    exit 1
fi

# Refresh the token and output only the access token
curl -s -X POST \
  "https://${SNOWFLAKE_ACCOUNT_IDENTIFIER}.snowflakecomputing.com/oauth/token-request" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=refresh_token' \
  --data-urlencode "refresh_token=${OAUTH_REFRESH_TOKEN}" \
  --data-urlencode "client_id=${OAUTH_CLIENT_ID}" \
  --data-urlencode "client_secret=${OAUTH_CLIENT_SECRET}" \
| python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('access_token', 'ERROR: ' + str(data)))"
