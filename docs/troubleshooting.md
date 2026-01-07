# Troubleshooting Guide

Common issues and solutions for Snowflake MCP with Claude Code.

## Table of Contents

- [OAuth Issues](#oauth-issues)
- [Token Issues](#token-issues)
- [MCP Connection Issues](#mcp-connection-issues)
- [Permission Issues](#permission-issues)
- [Configuration Issues](#configuration-issues)

---

## OAuth Issues

### Issue: Browser Doesn't Open

**Symptoms:**
- Script says "opening browser" but nothing happens
- No browser window appears

**Solutions:**

1. **Manually open the URL:**
   ```bash
   # The script will print the URL
   # Copy and paste it into your browser manually
   ```

2. **Check browser command:**
   ```bash
   # macOS
   which open

   # Linux
   which xdg-open

   # If missing, install appropriate tools
   ```

### Issue: Callback Not Received

**Symptoms:**
- Script waits indefinitely
- "Timeout waiting for authorization" error

**Solutions:**

1. **Check if port 3000 is in use:**
   ```bash
   lsof -i :3000
   # If occupied, kill the process or change port
   ```

2. **Verify redirect URI matches:**
   ```sql
   -- In Snowflake, check your OAuth integration
   DESC SECURITY INTEGRATION claude_code_mcp_oauth;

   -- OAUTH_REDIRECT_URI should be exactly:
   -- http://127.0.0.1:3000/oauth/callback
   ```

3. **Manually extract code:**
   - Complete authorization in browser
   - When redirected, browser shows "Connection Refused"
   - Copy the `code=...` from URL
   - Create file: `echo "YOUR_CODE" > /tmp/snowflake_oauth_code.txt`

### Issue: Invalid Grant Error

**Symptoms:**
```json
{
  "error": "invalid_grant",
  "message": "The provided grant or refresh token is invalid"
}
```

**Solutions:**

1. **Check client credentials:**
   - Verify `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` in `.env`
   - Re-run: `SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('...')`

2. **Authorization code expired:**
   - Authorization codes are single-use
   - Run `./setup.sh oauth` again

3. **Verify OAuth integration is enabled:**
   ```sql
   DESC SECURITY INTEGRATION claude_code_mcp_oauth;
   -- Ensure ENABLED = true
   ```

---

## Token Issues

### Issue: Access Token Expired

**Symptoms:**
```json
{
  "code": "390318",
  "message": "OAuth access token expired"
}
```

**Solutions:**

Tokens expire every 10 minutes. Refresh:
```bash
export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
```

**Make it easier with alias:**
```bash
# Add to ~/.zshrc or ~/.bashrc
alias refresh-mcp='export SNOWFLAKE_MCP_TOKEN=$(~/path/to/scripts/refresh_token.sh)'

# Then just run
refresh-mcp
```

### Issue: Refresh Token Expired

**Symptoms:**
```json
{
  "error": "invalid_grant",
  "message": "Refresh token is invalid or expired"
}
```

**Solutions:**

Refresh tokens last ~90 days. Re-authenticate:
```bash
./setup.sh oauth
```

This will get a new refresh token and update `.env` automatically.

### Issue: Token Not Found

**Symptoms:**
```
ERROR: OAUTH_REFRESH_TOKEN not set in .env
```

**Solutions:**

1. **Run OAuth flow first:**
   ```bash
   ./setup.sh oauth
   ```

2. **Manually add to .env:**
   - Run OAuth flow
   - Copy `refresh_token` from output
   - Add to `.env`: `OAUTH_REFRESH_TOKEN=ver:2-hint:...`

---

## MCP Connection Issues

### Issue: 404 Not Found

**Symptoms:**
```
HTTP 404
```

**Root Cause:** Wrong endpoint URL pattern

**Solutions:**

1. **Verify endpoint pattern:**
   ```
   Correct: /api/v2/databases/{DB}/schemas/{SCHEMA}/mcp-servers/{NAME}

   Wrong:
   - /api/v2/cortex/mcp/{NAME}
   - /api/mcp/{NAME}
   - /mcp/{NAME}
   ```

2. **Check .env configuration:**
   ```bash
   # Verify these are set correctly
   grep -E "MCP_(DATABASE|SCHEMA|SERVER_NAME)" .env
   ```

3. **Test endpoint manually:**
   ```bash
   ./setup.sh test
   ```

### Issue: Connection Refused

**Symptoms:**
```
curl: (7) Failed to connect to ... port 443
```

**Solutions:**

1. **Check network connectivity:**
   ```bash
   ping your-account.snowflakecomputing.com
   ```

2. **Verify account identifier:**
   ```bash
   # Should be: ORGNAME-ACCOUNTNAME
   # Not just: ACCOUNTNAME
   echo $SNOWFLAKE_ACCOUNT_IDENTIFIER
   ```

3. **Check firewall/VPN:**
   - Ensure Snowflake is accessible
   - Try from different network

### Issue: SSL Certificate Error

**Symptoms:**
```
SSL: CERTIFICATE_VERIFY_FAILED
```

**Solutions:**

1. **Update certificates:**
   ```bash
   # macOS
   /Applications/Python\ 3.x/Install\ Certificates.command

   # Linux
   sudo update-ca-certificates
   ```

2. **Verify account URL:**
   ```bash
   # Test with curl
   curl https://your-account.snowflakecomputing.com
   ```

---

## Permission Issues

### Issue: MCP Server Not Found

**Symptoms:**
```json
{
  "error": "MCP server does not exist or access is not authorized"
}
```

**Solutions:**

1. **Verify MCP server exists:**
   ```sql
   SHOW MCP SERVERS IN DATABASE your_database;
   ```

2. **Grant permissions:**
   ```sql
   GRANT USAGE ON DATABASE your_db TO ROLE your_role;
   GRANT USAGE ON SCHEMA your_db.your_schema TO ROLE your_role;
   GRANT USAGE ON MCP SERVER your_db.your_schema.your_mcp_server TO ROLE your_role;
   ```

3. **Check current role:**
   ```sql
   SELECT CURRENT_ROLE();

   -- OAuth token uses role from scope
   -- Check token response for: "scope": "session:role:YOUR_ROLE"
   ```

### Issue: Cortex Search Service Not Found

**Symptoms:**
```json
{
  "error": "Cortex Search Service ... does not exist or access is not authorized"
}
```

**Solutions:**

1. **Verify service exists:**
   ```sql
   SHOW CORTEX SEARCH SERVICES IN DATABASE your_database;
   ```

2. **Check MCP server configuration:**
   ```sql
   DESCRIBE MCP SERVER your_mcp_server;

   -- Verify identifier matches service name exactly (case-sensitive)
   ```

3. **Grant permissions:**
   ```sql
   GRANT USAGE ON CORTEX SEARCH SERVICE your_db.your_schema.your_service
   TO ROLE your_role;
   ```

4. **Verify identifier format:**
   ```sql
   -- Must be fully qualified and UPPERCASE
   -- Correct: AICOLLEGE.PUBLIC.GONG_CALLS_SEARCH_ENRICHED
   -- Wrong:  aicollege.public.gong_calls_search_enriched
   ```

---

## Configuration Issues

### Issue: .env File Not Found

**Symptoms:**
```
ERROR: .env file not found!
```

**Solutions:**

```bash
# Create from template
./setup.sh init

# Or manually
cp .env.example .env
```

### Issue: Missing Environment Variables

**Symptoms:**
```
ERROR: Missing required environment variables
```

**Solutions:**

1. **Check which variables are missing:**
   ```bash
   cat .env | grep -E "^[A-Z]"
   ```

2. **Ensure all required variables are set:**
   ```bash
   # Required:
   SNOWFLAKE_ACCOUNT_IDENTIFIER=ORGNAME-ACCOUNTNAME
   OAUTH_CLIENT_ID=your_id
   OAUTH_CLIENT_SECRET=your_secret
   MCP_DATABASE=YOUR_DB
   MCP_SCHEMA=YOUR_SCHEMA
   MCP_SERVER_NAME=your_server
   ```

### Issue: Claude Code Not Finding MCP Server

**Symptoms:**
```bash
claude mcp list
# Shows: ✗ Failed to connect
```

**Solutions:**

1. **Verify .mcp.json exists:**
   ```bash
   cat ~/.mcp.json
   ```

2. **Regenerate config:**
   ```bash
   ./setup.sh configure
   ```

3. **Check token is set:**
   ```bash
   echo $SNOWFLAKE_MCP_TOKEN
   # Should show: ver:1-hint:...
   ```

4. **Test manually:**
   ```bash
   export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
   claude mcp list
   ```

---

## Debug Mode

### Enable Verbose Logging

Add to scripts for debugging:

```bash
# In oauth_flow.sh or refresh_token.sh
set -x  # Enable debug output
```

### Test Each Step

```bash
# 1. Test environment
source .env
echo $SNOWFLAKE_ACCOUNT_IDENTIFIER

# 2. Test token refresh
./scripts/refresh_token.sh

# 3. Test MCP endpoint
./setup.sh test

# 4. Test with Claude Code
export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
claude mcp list
```

### Check Logs

```bash
# Claude Code logs (if available)
tail -f ~/.claude-code/logs/*.log

# System logs
# macOS
tail -f /var/log/system.log

# Linux
journalctl -f
```

---

## Getting Help

If you're still stuck:

1. **Check the detailed guide:**
   - [docs/detailed-guide.md](detailed-guide.md)

2. **Review comparison with other approaches:**
   - [docs/comparison.md](comparison.md)

3. **File an issue:**
   - https://github.com/yourusername/snowflake-mcp-claude-code/issues
   - Include:
     - Error messages (redact credentials!)
     - Output of `./setup.sh test`
     - Snowflake version
     - Operating system

4. **Community resources:**
   - [Snowflake Community](https://community.snowflake.com/)
   - [Claude Code Discord](https://discord.gg/claude-code)

---

## Common Patterns

### Daily Usage Pattern

```bash
# Morning: Get fresh token
refresh-mcp

# Work with Claude
claude
> "Search for calls mentioning X"

# Later: Token expired after 10 min
# Just refresh again
refresh-mcp
claude
```

### Team Deployment Pattern

See [docs/org-deployment.md](org-deployment.md) for multi-user strategies.

### CI/CD Pattern

```yaml
# Example GitHub Actions
- name: Refresh Snowflake Token
  run: |
    export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
  env:
    OAUTH_CLIENT_ID: ${{ secrets.OAUTH_CLIENT_ID }}
    OAUTH_CLIENT_SECRET: ${{ secrets.OAUTH_CLIENT_SECRET }}
    OAUTH_REFRESH_TOKEN: ${{ secrets.OAUTH_REFRESH_TOKEN }}
```

---

## Prevention Tips

1. **Set up shell alias** - avoid manual token refresh
2. **Monitor token expiry** - refresh tokens expire in 90 days
3. **Use version control** - track .env.example, not .env
4. **Regular testing** - run `./setup.sh test` periodically
5. **Keep credentials secure** - never commit .env or tokens
6. **Document your setup** - note any custom configurations
7. **Update regularly** - pull latest repo changes

---

**Last Updated:** 2026-01-06
