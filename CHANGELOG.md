# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- PKCE support for OAuth flow
- Windows compatibility improvements
- Docker container option
- Automated testing suite
- Token service for team deployments

## [1.0.0] - 2026-01-06

### Added
- Initial release
- OAuth 2.0 authorization flow with local callback server
- Token refresh script for daily usage
- Environment-based configuration (.env)
- Setup wizard with interactive commands
- MCP connection testing tools
- Comprehensive documentation:
  - Quick start guide (README.md)
  - Detailed setup guide (docs/detailed-guide.md)
  - Troubleshooting guide (docs/troubleshooting.md)
  - Organization deployment strategies (docs/org-deployment.md)
  - Comparison with other approaches (docs/comparison.md)
- MIT License
- Contributing guidelines
- .gitignore for security (prevents committing credentials)

### Features
- **OAuth Flow (`scripts/oauth_flow.sh`)**
  - Automated browser-based authentication
  - Local callback server on port 3000
  - Automatic token exchange
  - Refresh token saved to .env

- **Token Refresh (`scripts/refresh_token.sh`)**
  - Quick token refresh without re-authentication
  - Outputs only access_token for easy export
  - Handles token expiration gracefully

- **Setup Wizard (`setup.sh`)**
  - `./setup.sh init` - Initialize .env
  - `./setup.sh oauth` - Run OAuth flow
  - `./setup.sh configure` - Generate .mcp.json
  - `./setup.sh test` - Test MCP connection

- **Templates**
  - .env.example - Environment configuration template
  - .mcp.json.example - Claude Code MCP configuration template

### Security
- Credentials never committed (enforced by .gitignore)
- Environment-based secrets management
- OAuth 2.0 authorization code flow
- Refresh token rotation support

### Supported Platforms
- macOS (fully tested)
- Linux (compatible, community tested)
- Windows (partial support via WSL)

### Requirements
- Python 3.7+
- curl
- Claude Code CLI
- Snowflake account with:
  - OAuth security integration
  - MCP server configured
  - Cortex Search Service (or other tools)

## [0.1.0] - 2026-01-05 [YANKED]

### Added
- Initial prototype
- Manual OAuth flow
- Basic token management

### Removed
- Yanked due to hardcoded credentials issue

---

## Version History

### Current: v1.0.0
- First stable release
- Production-ready
- Comprehensive documentation
- Full OAuth implementation

### Upcoming: v1.1.0 (Planned)
- PKCE support
- Enhanced Windows support
- Automated tests
- Docker option

---

## Migration Notes

### From Manual Setup to v1.0.0

If you were using manual scripts:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/snowflake-mcp-claude-code.git
   cd snowflake-mcp-claude-code
   ```

2. Create .env from your existing values:
   ```bash
   cp .env.example .env
   # Copy your OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, etc.
   ```

3. If you have a refresh token:
   ```bash
   # Add to .env
   echo "OAUTH_REFRESH_TOKEN=your_token" >> .env
   ```

4. Generate .mcp.json:
   ```bash
   ./setup.sh configure
   ```

5. Test:
   ```bash
   ./setup.sh test
   ```

---

## Notes

- All versions follow semantic versioning
- Breaking changes will be clearly marked
- Deprecated features will be maintained for at least one minor version
- Security fixes will be backported to recent versions

---

[Unreleased]: https://github.com/yourusername/snowflake-mcp-claude-code/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yourusername/snowflake-mcp-claude-code/releases/tag/v1.0.0
[0.1.0]: https://github.com/yourusername/snowflake-mcp-claude-code/releases/tag/v0.1.0
