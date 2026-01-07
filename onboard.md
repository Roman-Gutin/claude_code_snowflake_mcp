# Onboarding Guide for Claude Code

This guide provides instructions for Claude Code to help users set up their Snowflake MCP connection interactively.

## Overview

When a user wants to set up this Snowflake MCP repository, Claude Code should guide them through an interactive onboarding process by asking questions, gathering information, and configuring their environment.

## Onboarding Flow

### Phase 1: Welcome and Prerequisites Check

**Claude Code should:**

1. Welcome the user to the Snowflake MCP for Claude Code setup
2. Explain what will be accomplished:
   - Connect Claude Code to Snowflake MCP servers
   - Set up OAuth authentication
   - Configure environment variables
   - Test the connection

3. Verify prerequisites by asking:
   ```
   "Let's make sure you have everything needed. Do you have:
   - A Snowflake account with access to create OAuth integrations?
   - An MCP server already configured in Snowflake?
   - Python 3.7+ and curl installed on your system?"
   ```

4. If they don't have an MCP server yet, ask:
   ```
   "Do you need help creating an MCP server in Snowflake first, or do you
   already have one configured?"
   ```

### Phase 2: Gather Snowflake Information

**Ask these questions one at a time:**

1. **Snowflake Account Identifier**
   ```
   "What is your Snowflake account identifier?
   This is in the format: ORGNAME-ACCOUNTNAME
   (You can find this in your Snowflake URL or by running SELECT CURRENT_ACCOUNT() in Snowflake)"
   ```
   - Store as: `SNOWFLAKE_ACCOUNT_IDENTIFIER`

2. **MCP Server Location**
   ```
   "What database is your MCP server in?"
   ```
   - Store as: `MCP_DATABASE`

   ```
   "What schema is your MCP server in?"
   ```
   - Store as: `MCP_SCHEMA`

   ```
   "What is your MCP server name?"
   ```
   - Store as: `MCP_SERVER_NAME`

3. **MCP Server Friendly Name**
   ```
   "What would you like to call this MCP server in Claude Code?
   (This is just a friendly name, defaults to the server name)"
   ```
   - Store as: `MCP_FRIENDLY_NAME` (optional)

### Phase 3: OAuth Security Integration Setup

**Claude Code should:**

1. Check if they have an OAuth integration set up:
   ```
   "Do you already have an OAuth Security Integration configured in Snowflake
   for Claude Code? (yes/no)"
   ```

2. **If NO**, guide them through creating one:

   Show them this SQL to run in Snowflake:
   ```sql
   CREATE SECURITY INTEGRATION claude_code_mcp_oauth
     TYPE = OAUTH
     OAUTH_CLIENT = CUSTOM
     ENABLED = TRUE
     OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
     OAUTH_REDIRECT_URI = 'http://127.0.0.1:3000/oauth/callback'
     OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE;
   ```

   Ask:
   ```
   "Please run this SQL in your Snowflake account. Let me know when you're done."
   ```

3. **Get OAuth Credentials:**

   Show them this SQL:
   ```sql
   SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_CODE_MCP_OAUTH');
   ```

   Ask:
   ```
   "Now run this query to get your OAuth credentials.
   What is the OAUTH_CLIENT_ID from the result?"
   ```
   - Store as: `OAUTH_CLIENT_ID`

   ```
   "What is the OAUTH_CLIENT_SECRET from the result?"
   ```
   - Store as: `OAUTH_CLIENT_SECRET`

4. **If YES (they already have OAuth)**, just ask:
   ```
   "What is your OAuth integration name?"
   "What is your OAUTH_CLIENT_ID?"
   "What is your OAUTH_CLIENT_SECRET?"
   ```

### Phase 4: Create .env File

**Claude Code should:**

1. Use the gathered information to create a `.env` file:
   ```
   "Great! I have all the information I need. Let me create your .env file."
   ```

2. Use the Write tool to create `.env` with:
   ```bash
   # Snowflake MCP Configuration
   SNOWFLAKE_ACCOUNT_IDENTIFIER={user's account}
   OAUTH_CLIENT_ID={user's client id}
   OAUTH_CLIENT_SECRET={user's client secret}
   OAUTH_REDIRECT_URI=http://127.0.0.1:3000/oauth/callback
   OAUTH_REFRESH_TOKEN=

   MCP_DATABASE={user's database}
   MCP_SCHEMA={user's schema}
   MCP_SERVER_NAME={user's server name}
   MCP_FRIENDLY_NAME={user's friendly name}
   ```

3. Confirm:
   ```
   "✓ Created .env file with your Snowflake configuration"
   ```

### Phase 5: Run OAuth Authorization Flow

**Claude Code should:**

1. Explain the OAuth flow:
   ```
   "Now we need to authorize Claude Code to access your Snowflake MCP server.
   This will:
   1. Start a local web server on port 3000
   2. Open your browser to Snowflake login
   3. Capture the authorization code
   4. Exchange it for access and refresh tokens

   Ready to proceed?"
   ```

2. Run the OAuth flow:
   ```bash
   cd ~/snowflake-mcp-claude-code-clean && ./scripts/oauth_flow.sh
   ```

3. Guide them through any issues:
   - If port 3000 is in use, help them find and kill the process
   - If browser doesn't open, provide the URL manually
   - If authorization fails, help troubleshoot

4. Verify the refresh token was added to `.env`:
   ```
   "✓ OAuth authorization successful! Your refresh token has been saved to .env"
   ```

### Phase 6: Configure Claude Code

**Claude Code should:**

1. Generate the `.mcp.json` file:
   ```bash
   cd ~/snowflake-mcp-claude-code-clean && ./setup.sh configure
   ```

   Or manually create it:
   ```json
   {
     "mcpServers": {
       "{MCP_FRIENDLY_NAME}": {
         "type": "http",
         "url": "https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/databases/{DB}/schemas/{SCHEMA}/mcp-servers/{SERVER}",
         "headers": {
           "Authorization": "Bearer ${SNOWFLAKE_MCP_TOKEN}"
         }
       }
     }
   }
   ```

2. Explain token refresh:
   ```
   "Your MCP configuration is ready! Note that access tokens expire every 10 minutes.
   Before starting Claude Code, you'll need to refresh your token:

   export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)

   Or add this alias to your ~/.zshrc or ~/.bashrc:
   alias refresh-mcp='export SNOWFLAKE_MCP_TOKEN=$(~/snowflake-mcp-claude-code-clean/scripts/refresh_token.sh)'"
   ```

### Phase 7: Test the Connection

**Claude Code should:**

1. Refresh the token and test:
   ```bash
   cd ~/snowflake-mcp-claude-code-clean && ./setup.sh test
   ```

2. If successful:
   ```
   "🎉 Success! Your Snowflake MCP connection is working!

   Next steps:
   1. Refresh your token: export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
   2. Start Claude Code: claude
   3. Try a query like: 'Search for calls mentioning [topic]'

   Your setup is complete!"
   ```

3. If there are errors:
   - Check endpoint URL format
   - Verify permissions
   - Check token validity
   - Verify MCP server exists

### Phase 8: Summary and Next Steps

**Claude Code should provide:**

1. A summary of what was configured:
   ```
   "Setup Summary:
   ✓ Snowflake Account: {account}
   ✓ MCP Server: {database}.{schema}.{server}
   ✓ OAuth Integration: Configured and authorized
   ✓ Claude Code: Ready to connect

   Files created:
   - .env (with your credentials)
   - .mcp.json (Claude Code configuration)

   Daily usage:
   1. refresh-mcp
   2. claude

   For help: See README.md or docs/"
   ```

2. Set up the shell alias automatically:

   Detect the user's shell and append to the appropriate config file (`~/.zshrc` for zsh or `~/.bashrc` for bash):
   ```bash
   # Snowflake MCP token refresh
   alias refresh-mcp='export SNOWFLAKE_MCP_TOKEN=$(~/snowflake-mcp-claude-code-clean/scripts/refresh_token.sh)'
   ```

   Then source the config file to make it available immediately:
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```

## Error Handling

### Common Issues and Responses

1. **OAuth Integration Already Exists**
   ```
   "It looks like you already have an OAuth integration with that name.
   Would you like to:
   1. Use the existing integration (you'll need the client ID and secret)
   2. Create a new one with a different name
   3. Drop and recreate the existing one"
   ```

2. **Port 3000 In Use**
   ```bash
   lsof -i :3000
   # Show them the process and ask if they want to kill it
   ```

3. **MCP Server Not Found**
   ```
   "I couldn't find the MCP server at {database}.{schema}.{server}.
   Let me help you verify:
   - Run this in Snowflake: SHOW MCP SERVERS IN DATABASE {database};

   Do you see your server in the list?"
   ```

4. **Permission Denied**
   ```
   "It looks like you don't have permission to access the MCP server.
   You may need to run these grants in Snowflake:

   GRANT USAGE ON DATABASE {database} TO ROLE {your_role};
   GRANT USAGE ON SCHEMA {database}.{schema} TO ROLE {your_role};
   GRANT USAGE ON MCP SERVER {database}.{schema}.{server} TO ROLE {your_role};"
   ```

5. **Token Expired During Setup**
   ```
   "Your token expired. Let me refresh it and try again..."
   ```

## Tips for Claude Code

1. **Be Patient**: Users may need time to run SQL in Snowflake
2. **Validate Input**: Check that account identifiers and names are in the correct format
3. **Show Examples**: Provide examples of what valid inputs look like
4. **Test Incrementally**: Test each step before moving to the next
5. **Save Progress**: Write the .env file as information is gathered
6. **Clear Instructions**: Be specific about what needs to be done and where
7. **Celebrate Success**: Acknowledge when steps are completed successfully

## Advanced Setup Options

If users need additional configuration:

1. **Multiple MCP Servers**: Guide them through adding multiple servers to `.mcp.json`
2. **Custom OAuth Settings**: Support different redirect URIs or port numbers
3. **Proxy Configuration**: Help configure proxy settings if needed
4. **Organization-Wide Deployment**: Point to `docs/org-deployment.md` for team setup

## Resuming Failed Setup

If setup is interrupted:

1. Check what's already configured:
   ```bash
   cat .env
   ```

2. Identify what's missing and resume from that phase
3. Don't ask for information that's already in `.env`

## Example Conversation Flow

```
Claude: "Welcome! Let's set up your Snowflake MCP connection for Claude Code.
I'll ask you a few questions to get everything configured.

First, what is your Snowflake account identifier?
(Format: ORGNAME-ACCOUNTNAME)"

User: "MYORG-MYACCOUNT"

Claude: "Great! What database is your MCP server in?"

User: "PROD_DB"

Claude: "And what schema?"

User: "PUBLIC"

Claude: "What's the MCP server name?"

User: "sales_mcp"

Claude: "Perfect! Do you already have an OAuth Security Integration configured
for Claude Code? (yes/no)"

User: "no"

Claude: "No problem! Please run this SQL in Snowflake:

[Shows CREATE SECURITY INTEGRATION SQL]

Let me know when you're done."

User: "Done"

Claude: "Excellent! Now run this query to get your OAuth credentials:

[Shows SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS SQL]

What is the OAUTH_CLIENT_ID from the result?"

[... continues through all phases ...]

Claude: "🎉 All set! Your Snowflake MCP is connected to Claude Code!"
```

## Security Reminders

Always remind users:
- Never commit `.env` files
- Keep OAuth credentials secure
- Rotate credentials regularly
- Use least-privilege roles
- Don't share refresh tokens

---

**This guide enables Claude Code to provide a smooth, interactive onboarding experience for Snowflake MCP users.**
