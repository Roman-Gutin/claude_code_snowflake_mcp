# Contributing to Snowflake MCP for Claude Code

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

- **Search existing issues** first to avoid duplicates
- Use the issue template if available
- Include:
  - Clear description of the problem
  - Steps to reproduce
  - Expected vs actual behavior
  - Environment details (OS, Python version, etc.)
  - Error messages (redact credentials!)

### Suggesting Enhancements

- Open an issue with the enhancement label
- Describe the feature and use case
- Explain why it would be useful
- Consider implementation complexity

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed

4. **Test thoroughly**
   ```bash
   ./setup.sh test
   ```

5. **Commit with clear messages**
   ```bash
   git commit -m "Add feature: description"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/snowflake-mcp-claude-code.git
cd snowflake-mcp-claude-code

# Create .env for testing
cp .env.example .env
# Fill in your test credentials

# Make changes
# Test with:
./setup.sh test
```

## Code Style

### Bash Scripts

- Use `#!/bin/bash` shebang
- Enable strict mode: `set -e`
- Use double quotes for variables
- Add comments for non-obvious code
- Use functions for reusable code

**Example:**
```bash
#!/bin/bash

set -e

# Function to do something
do_something() {
    local arg="$1"
    echo "Processing: ${arg}"
}

do_something "test"
```

### Documentation

- Use Markdown format
- Keep line length reasonable (80-100 chars)
- Include code examples
- Add table of contents for long docs

## Testing

Before submitting:

```bash
# Test environment setup
./setup.sh init
source .env

# Test OAuth flow (requires real Snowflake account)
./setup.sh oauth

# Test token refresh
./scripts/refresh_token.sh

# Test MCP connection
./setup.sh test
```

## Documentation Updates

When adding features, update:

- [ ] README.md - Quick start and main documentation
- [ ] docs/detailed-guide.md - Detailed walkthrough (if applicable)
- [ ] docs/troubleshooting.md - Common issues (if applicable)
- [ ] CHANGELOG.md - Add entry for the change

## Commit Message Guidelines

Use conventional commit format:

```
type(scope): subject

body (optional)
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

**Examples:**
```
feat(oauth): add PKCE support for enhanced security

fix(refresh): handle expired refresh token gracefully

docs(readme): add troubleshooting section for 404 errors
```

## Code Review Process

1. Maintainer reviews PR
2. Feedback or approval
3. Make requested changes if needed
4. Once approved, maintainer merges

## Areas for Contribution

### High Priority

- [ ] Add PKCE support to OAuth flow
- [ ] Implement token service for teams
- [ ] Add Windows support
- [ ] Create Docker container option
- [ ] Add automated tests

### Medium Priority

- [ ] Improve error messages
- [ ] Add role-based access examples
- [ ] Create video tutorials
- [ ] Add Jupyter notebook examples
- [ ] Support multiple MCP servers

### Low Priority

- [ ] Add shell completion
- [ ] Create GUI wrapper
- [ ] Add metrics/monitoring
- [ ] Support other OAuth providers

## Questions?

- Open a discussion: https://github.com/yourusername/snowflake-mcp-claude-code/discussions
- Email: your.email@example.com

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Thank You!

Your contributions help make this project better for everyone. 🙏
