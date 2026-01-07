# Comparison: Streamlit MCP Client vs Claude Code MCP Integration

## Overview

Both solutions authenticate to Snowflake MCP servers using OAuth, but they serve different purposes and have different architectures.

---

## Side-by-Side Comparison

| Aspect | Streamlit Repo (GitHub) | What We Built (Claude Code) |
|--------|-------------------------|---------------------------|
| **Purpose** | Standalone web-based MCP query client | Integration of Snowflake MCP into Claude Code CLI |
| **User Interface** | Streamlit web GUI with login button | Command-line interface (CLI) |
| **OAuth Flow** | Authorization Code + PKCE | Authorization Code (standard) |
| **OAuth Callback** | Streamlit handles redirect automatically | Custom Python server on localhost:3000 |
| **Token Storage** | In-memory (Streamlit session) | Environment variable + refresh script |
| **Token Lifecycle** | Ephemeral (lost on browser close) | Persistent (refresh token saved) |
| **Role Binding** | Explicit via `session:role:ROLE_NAME` scope | Implicit (uses user's default or token role) |
| **Multi-User Pattern** | Each user runs their own Streamlit instance | Centralized token service (optional) |
| **Integration** | Standalone Python app | Native Claude Code MCP server |
| **Query Interface** | Custom chat UI in Streamlit | Claude AI natural language |
| **Deployment** | Web app (localhost or cloud) | CLI tool on user's machine |

---

## Detailed Differences

### 1. **Application Type**

**Streamlit Repo:**
```python
# Streamlit web application
streamlit run mcp_client_oauth.py

# Browser opens with GUI
# User clicks "Login with Snowflake"
# Chat interface for queries
```

**What We Built:**
```bash
# CLI application
export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)
claude

# Terminal interface
# Natural language queries to Claude
```

### 2. **OAuth Implementation**

**Streamlit Repo (with PKCE):**
```python
# Generates code_verifier and code_challenge
code_verifier = secrets.token_urlsafe(32)
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).decode().rstrip('=')

# Authorization URL includes PKCE parameters
auth_url = f"{base_url}/oauth/authorize?client_id={client_id}&redirect_uri={redirect_uri}&response_type=code&scope=session:role:{role}&code_challenge={code_challenge}&code_challenge_method=S256"

# Token exchange includes code_verifier
data = {
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': redirect_uri,
    'client_id': client_id,
    'client_secret': client_secret,
    'code_verifier': code_verifier  # PKCE protection
}
```

**What We Built (Standard OAuth):**
```bash
# Standard Authorization Code flow
auth_url = "https://${ACCOUNT}.snowflakecomputing.com/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code"

# Token exchange (no PKCE)
curl -X POST \
  'https://${ACCOUNT}.snowflakecomputing.com/oauth/token-request' \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode "code=${AUTH_CODE}" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}"
```

**Key Difference:** PKCE adds security against authorization code interception attacks. The Streamlit repo is more secure for public clients.

### 3. **OAuth Callback Handling**

**Streamlit Repo:**
```python
# Streamlit automatically handles OAuth callback
# Uses query parameters: ?code=...&state=...
import streamlit as st

if 'code' in st.query_params:
    code = st.query_params['code']
    # Exchange code for token
```

Streamlit's built-in routing handles the redirect automatically. No separate server needed.

**What We Built:**
```python
# Custom HTTP server to capture callback
class OAuthCallbackHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        params = parse_qs(parsed_path.query)

        if 'code' in params:
            auth_code = params['code'][0]
            # Save to file for bash script
```

We had to build a temporary HTTP server because CLI tools don't have built-in web routing.

### 4. **Role-Based Access Control**

**Streamlit Repo:**
```python
# Explicitly passes role in OAuth scope
role = os.getenv('ROLE')
scope = f"session:role:{role}"

auth_url = f"{base_url}/oauth/authorize?...&scope={scope}"
```

This binds the OAuth token to a specific Snowflake role, enabling:
- Different users accessing different MCP servers based on role
- Fine-grained RBAC for MCP tools
- Role switching by re-authenticating

**What We Built:**
```bash
# No explicit role in scope
# Token uses user's default role or role from SSO
auth_url = "...?client_id=${CLIENT_ID}&response_type=code"
```

The OAuth token scope in our implementation was:
```json
"scope": "refresh_token session:role:AICOLLEGE"
```

This was **automatically set by Snowflake** based on the user's session, not explicitly passed.

### 5. **Token Management**

**Streamlit Repo:**
```python
# Tokens stored in Streamlit session state
st.session_state['access_token'] = response_data['access_token']

# Lost when browser closes or session expires
# User must re-login
```

**What We Built:**
```bash
# Refresh token saved persistently
REFRESH_TOKEN="ver:2-hint:334663991305..."

# Access token refreshed on demand
export SNOWFLAKE_MCP_TOKEN=$(~/refresh_snowflake_mcp_token.sh)

# Refresh token valid for 90 days
```

### 6. **MCP Server Connection**

**Streamlit Repo:**
```python
# Direct HTTP calls to MCP server
def call_mcp_tool(access_token, query):
    url = f"https://{account}/api/v2/databases/{db}/schemas/{schema}/mcp-servers/{mcp_server}"

    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }

    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "search-tool",
            "arguments": {"query": query}
        }
    }

    response = requests.post(url, headers=headers, json=payload)
    return response.json()
```

**What We Built:**
```json
// .mcp.json - Claude Code handles MCP protocol
{
  "mcpServers": {
    "gong_mcp": {
      "type": "http",
      "url": "https://...snowflakecomputing.com/api/v2/databases/AICOLLEGE/schemas/PUBLIC/mcp-servers/gong_mcp",
      "headers": {
        "Authorization": "Bearer ${SNOWFLAKE_MCP_TOKEN}"
      }
    }
  }
}
```

Claude Code abstracts away the MCP protocol details. We just configure the endpoint.

### 7. **User Experience**

**Streamlit Repo:**
```
1. Run: streamlit run mcp_client_oauth.py
2. Browser opens with web interface
3. Click "Login with Snowflake"
4. Authenticate in browser
5. Redirected back to Streamlit
6. Type queries in chat interface
7. See results in web UI
```

**What We Built:**
```
1. Run: export SNOWFLAKE_MCP_TOKEN=$(~/refresh_token.sh)
2. Browser opens for OAuth (one-time or when expired)
3. Authenticate in browser
4. Terminal shows success
5. Run: claude
6. Type natural language to Claude
7. Claude queries MCP automatically
8. See results in terminal
```

---

## Architecture Diagrams

### Streamlit Repo Architecture

```
┌──────────────┐
│    User      │
│  (Browser)   │
└──────┬───────┘
       │
       │ HTTP (port 8501)
       ↓
┌──────────────────┐
│    Streamlit     │
│   Application    │
│                  │
│  • OAuth Flow    │
│  • Token Storage │
│  • MCP Client    │
│  • Chat UI       │
└──────┬───────────┘
       │
       │ OAuth
       ↓
┌──────────────────┐      MCP Protocol
│   Snowflake      │←─────────────────┐
│   OAuth Server   │                  │
└──────────────────┘                  │
                                      │
                           ┌──────────┴──────┐
                           │  Snowflake MCP  │
                           │     Server      │
                           └─────────────────┘
```

### What We Built Architecture

```
┌──────────────┐
│    User      │
│  (Terminal)  │
└──────┬───────┘
       │
       │ commands
       ↓
┌──────────────────┐
│   Claude Code    │
│      CLI         │
│                  │
│  • MCP Client    │
│  • AI Interface  │
└──────┬───────────┘
       │
       │ reads config
       ↓
┌──────────────────┐
│   .mcp.json      │
│                  │
│  • Endpoint URL  │
│  • Auth Header   │
└──────────────────┘
       │
       │ uses token from env
       ↓
┌──────────────────┐
│  $SNOWFLAKE_MCP_ │
│      TOKEN       │
│                  │
│  • From refresh  │
│  • script        │
└──────┬───────────┘
       │
       │ OAuth & MCP calls
       ↓
┌──────────────────┐
│   Snowflake      │
│                  │
│  • OAuth Server  │
│  • MCP Server    │
└──────────────────┘
```

---

## Security Comparison

### PKCE Protection

**Streamlit Repo: ✅ Has PKCE**
- More secure against authorization code interception
- Recommended for public clients
- Required for mobile/SPA apps

**What We Built: ❌ No PKCE**
- Standard OAuth flow
- Relies on client_secret confidentiality
- Acceptable for CLI tools with secure credential storage

### Token Storage

**Streamlit Repo:**
- ✅ Tokens in memory only
- ✅ Not persisted to disk
- ❌ Lost on session end (requires re-login)

**What We Built:**
- ✅ Refresh token enables long-term access
- ❌ Refresh token stored in script (security risk if not protected)
- ✅ Access token ephemeral (env variable)

### Best Practice for Production

**Streamlit Repo Approach:**
- Better for web applications
- Better for public-facing clients
- PKCE is industry best practice

**Our Approach:**
- Better for CLI tools
- Better for automated workflows
- Persistent refresh tokens reduce login friction

---

## When to Use Each Approach

### Use Streamlit Repo When:

1. **You want a web-based UI** for querying MCP servers
2. **Multiple users need separate instances** (each runs their own Streamlit app)
3. **You need PKCE security** for compliance
4. **Tokens should be ephemeral** (security requirement)
5. **You're building a custom MCP client** with specific UI needs
6. **Role-based routing** is critical (different users → different MCP servers)

### Use Our Claude Code Approach When:

1. **You want Claude AI** to query your MCP data
2. **CLI interface** is preferred
3. **Long-term token persistence** is acceptable (dev/internal use)
4. **Integration with existing Claude workflows** is needed
5. **Automated scripting** with Claude Code is the goal
6. **You want natural language interface** instead of custom UI

---

## Hybrid Approach: Best of Both Worlds

You could combine both approaches:

### Architecture

```
┌─────────────────┐
│ Streamlit App   │ ← Web UI for manual queries
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  Token Service  │ ← Centralized token management
│  (Our design)   │    • Stores refresh tokens
└────────┬────────┘    • Auto-refreshes
         │             • Role-based access
         ↓
┌─────────────────┐
│  Claude Code    │ ← CLI for AI-powered queries
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake MCP   │
└─────────────────┘
```

**Benefits:**
- ✅ Web UI for ad-hoc queries (Streamlit)
- ✅ CLI/AI for complex workflows (Claude Code)
- ✅ Centralized token management
- ✅ Single OAuth setup per user

---

## Key Takeaways

1. **Streamlit repo is a complete MCP client application** with web UI
2. **Our implementation integrates Snowflake MCP into Claude Code's existing MCP system**
3. **Streamlit has better security (PKCE)** but ephemeral tokens
4. **Our approach has persistent tokens** but requires more manual setup
5. **Streamlit is user-friendly** for non-technical users
6. **Claude Code approach is developer-friendly** for automation
7. **Both solve the same core problem:** Authenticate to Snowflake MCP via OAuth

---

## Migration Path

If you wanted to **enhance our implementation** with features from the Streamlit repo:

### Add PKCE to Our OAuth Flow

```bash
# In snowflake_oauth_flow.sh, add PKCE:

# Generate code verifier
CODE_VERIFIER=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

# Generate code challenge
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | python3 -c "
import sys
import hashlib
import base64
data = sys.stdin.read().encode()
hash = hashlib.sha256(data).digest()
challenge = base64.urlsafe_b64encode(hash).decode().rstrip('=')
print(challenge)
")

# Add to authorization URL
AUTH_URL="...&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

# Add to token exchange
--data-urlencode "code_verifier=${CODE_VERIFIER}"
```

### Add Role-Based Access

```bash
# In setup script, prompt for role
echo "Enter your Snowflake role:"
read ROLE

# Add to authorization URL
AUTH_URL="...&scope=session:role:${ROLE}"
```

### Add Token Rotation

```python
# Enhanced token service with automatic rotation
def rotate_refresh_token(username):
    """
    Snowflake refresh tokens can be rotated
    Returns new refresh token with extended validity
    """
    # Implementation details...
```

---

## Conclusion

Both approaches are valid and solve slightly different problems:

- **Streamlit repo** = Standalone web-based MCP query client
- **Our implementation** = Claude Code integration for AI-powered queries

Choose based on your use case:
- Need web UI? → Use Streamlit
- Need Claude AI? → Use our approach
- Need both? → Use hybrid architecture with shared token service

The core OAuth flow and MCP protocol are the same; the difference is in **presentation layer** and **token lifecycle management**.
