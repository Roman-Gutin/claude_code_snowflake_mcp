# Snowflake MCP for Claude Code

Connect [Claude Code](https://claude.ai/download) to your Snowflake-managed MCP (Model Context Protocol) servers using OAuth authentication.

## Features

- 🔐 **OAuth 2.0 Authentication** - Secure authorization flow with token refresh
- 🚀 **Easy Setup** - Clone, configure, and go
- 📝 **Environment-based Config** - No hardcoded credentials
- 🔄 **Automatic Token Refresh** - Scripts handle token lifecycle
- 🛠️ **Testing Tools** - Built-in connection testing
- 📚 **Complete Documentation** - Detailed guides and troubleshooting

## Prerequisites

- Python 3.7+
- curl
- [Claude Code CLI](https://claude.ai/download)
- Snowflake account with:
  - OAuth security integration created
  - MCP server configured
  - Cortex Search Service (or other MCP tools)

## Quick Start

### Interactive Onboarding with Claude Code

**New to this setup?** Use Claude Code to guide you through the entire onboarding process interactively!

```bash
# Clone the repository
git clone https://github.com/yourusername/snowflake-mcp-claude-code.git
cd snowflake-mcp-claude-code

# Start Claude Code in this directory
claude

# Then say: "Help me set up my Snowflake MCP connection using onboard.md"
```

Claude Code will ask you questions and configure everything automatically. See [onboard.md](onboard.md) for details on the interactive setup process.

### Manual Setup

Alternatively, you can set up manually:

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/snowflake-mcp-claude-code.git
cd snowflake-mcp-claude-code
```

### 2. Configure Environment

```bash
# Create .env from template
./setup.sh init

# Edit .env with your Snowflake credentials
nano .env  # or vim, code, etc.
```

Required values in `.env`:
- `SNOWFLAKE_ACCOUNT_IDENTIFIER` - Your Snowflake account (e.g., ORGNAME-ACCOUNTNAME)
- `OAUTH_CLIENT_ID` - From `SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS(...)`
- `OAUTH_CLIENT_SECRET` - From the same query
- `MCP_DATABASE`, `MCP_SCHEMA`, `MCP_SERVER_NAME` - Your MCP server location

### 3. Run OAuth Authorization

```bash
# Authenticate via browser and get tokens
./setup.sh oauth
```

This will:
- Start a local callback server
- Open your browser to Snowflake login
- Capture authorization code
- Exchange for access + refresh tokens
- Save refresh token to `.env`

### 4. Configure Claude Code

```bash
# Generate .mcp.json for Claude Code
./setup.sh configure
```

### 5. Test Connection

```bash
# Verify everything works
./setup.sh test
```

### 6. Use with Claude Code

```bash
# Get fresh access token
export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)

# Start Claude Code
claude

# Query your MCP server
# "Search for phone calls mentioning databricks"
```

## Daily Usage

### Option 1: Manual Token Refresh

```bash
# Refresh token (good for ~10 minutes)
export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)

# Start Claude Code
claude
```

### Option 2: Shell Alias (Recommended)

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Snowflake MCP token refresh
alias refresh-mcp='export SNOWFLAKE_MCP_TOKEN=$(~/path/to/snowflake-mcp-claude-code/scripts/refresh_token.sh)'
```

Then use:

```bash
refresh-mcp
claude
```

## Snowflake SQL REST API Tool

This repository includes a powerful command-line tool and Python module for executing SQL queries directly against Snowflake using the SQL REST API.

### Quick Start

```bash
# Execute a SQL query from command line
./sf-sql "SELECT CURRENT_USER()"

# Query your data
./sf-sql "SELECT * FROM aicollege.public.gong_calls_enriched LIMIT 10"

# Get JSON output
./sf-sql "SHOW TABLES IN SCHEMA aicollege.public" --json
```

### Python Module Usage

```python
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()
result = api.execute("SELECT COUNT(*) FROM mytable")
print(result['data'])
```

### Features

- OAuth 2.0 authentication with automatic token refresh
- Synchronous and asynchronous query execution
- Statement cancellation support
- Clean table or JSON output
- No JDBC or binary dependencies required

For complete documentation, see [docs/sql-api-tool.md](docs/sql-api-tool.md).

## Repository Structure

```
snowflake-mcp-claude-code/
├── README.md                 # This file
├── .env.example             # Environment template
├── .gitignore               # Git ignore rules
├── .mcp.json.example        # MCP config template
├── setup.sh                 # Main setup script
├── teardown.sh              # Reset and clean up configuration
├── snowflake_sql_api.py     # Python SQL REST API client
├── sf-sql                   # Command-line SQL tool
├── scripts/
│   ├── oauth_flow.sh        # OAuth authorization flow
│   └── refresh_token.sh     # Token refresh script
└── docs/
    ├── detailed-guide.md    # Complete setup guide
    ├── troubleshooting.md   # Common issues and solutions
    ├── org-deployment.md    # Team deployment strategies
    └── sql-api-tool.md      # SQL REST API tool documentation
```

## Setup Commands

| Command | Description |
|---------|-------------|
| `./setup.sh init` | Create .env from template |
| `./setup.sh oauth` | Run OAuth flow to get tokens |
| `./setup.sh configure` | Generate Claude Code .mcp.json |
| `./setup.sh test` | Test MCP connection |

## Snowflake Setup

Before using this tool, you need to configure Snowflake:

### 1. Create OAuth Security Integration

```sql
CREATE SECURITY INTEGRATION claude_code_mcp_oauth
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://127.0.0.1:3000/oauth/callback'
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE;
```

### 2. Get OAuth Credentials

```sql
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_CODE_MCP_OAUTH');
```

Save the `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` to your `.env` file.

### 3. Create MCP Server

```sql
USE DATABASE your_database;
USE SCHEMA your_schema;

CREATE OR REPLACE MCP SERVER your_mcp_server
  FROM SPECIFICATION $
    tools:
      - name: "search-tool"
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        identifier: "YOUR_DB.YOUR_SCHEMA.YOUR_CORTEX_SEARCH_SERVICE"
        description: "Search tool description"
        title: "Search Title" $;
```

**Important:** Use fully qualified names in UPPERCASE for the identifier.

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SNOWFLAKE_ACCOUNT_IDENTIFIER` | Your Snowflake account | `ORGNAME-ACCOUNTNAME` |
| `OAUTH_CLIENT_ID` | OAuth client ID from Snowflake | `6IQDfL...` |
| `OAUTH_CLIENT_SECRET` | OAuth client secret | `/BXfFh...` |
| `OAUTH_REDIRECT_URI` | OAuth callback URL | `http://127.0.0.1:3000/oauth/callback` |
| `OAUTH_REFRESH_TOKEN` | Refresh token (auto-populated) | `ver:2-hint:...` |
| `MCP_DATABASE` | Snowflake database name | `AICOLLEGE` |
| `MCP_SCHEMA` | Snowflake schema name | `PUBLIC` |
| `MCP_SERVER_NAME` | MCP server name | `gong_mcp` |
| `MCP_FRIENDLY_NAME` | Name for Claude Code | `gong_mcp` |

## Troubleshooting

### OAuth Authorization Fails

**Problem:** Browser doesn't redirect properly or code not captured

**Solutions:**
- Check that Snowflake OAuth redirect URI matches: `http://127.0.0.1:3000/oauth/callback`
- Ensure port 3000 is not in use: `lsof -i :3000`
- Try manually: Open the auth URL from script output and copy the code from browser address bar

### Token Expired Error

**Problem:** `OAuth access token expired`

**Solution:** Tokens expire every 10 minutes. Refresh:
```bash
export SNOWFLAKE_MCP_TOKEN=$(./scripts/refresh_token.sh)
```

### MCP Server Returns 404

**Problem:** `404 Not Found` when testing MCP endpoint

**Solutions:**
- Verify endpoint URL pattern: `/api/v2/databases/{DB}/schemas/{SCHEMA}/mcp-servers/{NAME}`
- Check MCP server exists: `SHOW MCP SERVERS IN DATABASE your_db;`
- Confirm database, schema, and server names are correct in `.env`

### Cortex Search Service Not Found

**Problem:** `Cortex Search Service ... does not exist`

**Solutions:**
- Verify Cortex Search Service exists: `SHOW CORTEX SEARCH SERVICES IN DATABASE your_db;`
- Check identifier in MCP server matches exactly (case-sensitive)
- Grant permissions: `GRANT USAGE ON CORTEX SEARCH SERVICE ... TO ROLE your_role;`

### Permission Denied

**Problem:** User doesn't have access to MCP server

**Solution:**
```sql
GRANT USAGE ON DATABASE your_db TO ROLE your_role;
GRANT USAGE ON SCHEMA your_db.your_schema TO ROLE your_role;
GRANT USAGE ON MCP SERVER your_db.your_schema.your_mcp_server TO ROLE your_role;
```

For more troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Security Notes

⚠️ **Important Security Practices:**

- Never commit `.env` file (already in `.gitignore`)
- Never commit `.mcp.json` with tokens
- Rotate OAuth credentials regularly
- Use least-privilege roles for MCP access
- Keep refresh tokens secure (they're valid for 90 days)

## Token Lifecycle

| Token Type | Duration | Purpose | Refresh Method |
|------------|----------|---------|----------------|
| Access Token | ~10 minutes | Authenticate MCP requests | Use refresh token |
| Refresh Token | ~90 days | Get new access tokens | Re-run OAuth flow |

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Documentation

- [Detailed Setup Guide](docs/detailed-guide.md) - Complete walkthrough
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues
- [Organization Deployment](docs/org-deployment.md) - Multi-user setup strategies
- [SQL REST API Tool](docs/sql-api-tool.md) - Direct SQL query tool and Python module

## Resources

- [Snowflake MCP Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Claude Code Documentation](https://code.claude.com/docs)
- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)

## Support

- 🐛 [Report Issues](https://github.com/yourusername/snowflake-mcp-claude-code/issues)
- 💬 [Discussions](https://github.com/yourusername/snowflake-mcp-claude-code/discussions)
- 📧 Email: your.email@example.com

## Acknowledgments

Built with ❤️ for the Claude Code and Snowflake communities.

---

**Note:** This is not an official Snowflake or Anthropic product.
