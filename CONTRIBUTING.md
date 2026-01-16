# Contributing to Claude Container

Thank you for your interest in contributing to Claude Container! We welcome bug reports, feature requests, and pull requests.

## Reporting Bugs

Found a bug? Please report it using [GitHub Issues](https://github.com/aubi-one-david/claude-container/issues).

When reporting a bug, include:
- A clear description of the issue
- Steps to reproduce the problem
- Expected behavior vs. actual behavior
- Environment details (OS, Podman version, Claude Code version)
- Relevant error messages or logs

## Submitting Pull Requests

We appreciate pull requests! Here's how to contribute:

1. **Fork and branch** - Fork the repository and create a feature branch from `main`
2. **Make changes** - Implement your fix or feature
3. **Test thoroughly** - Ensure all tests pass (see Testing section below)
4. **Build verification** - Verify the container builds successfully
5. **Submit PR** - Open a pull request with a clear description of your changes

## Code Style Guidelines

Keep it simple and follow existing patterns in the codebase:

- **Shell scripts** - Use standard POSIX shell conventions, add comments for complex logic
- **Documentation** - Keep READMEs and docs clear and concise
- **File organization** - Follow the existing directory structure:
  - `scripts/` - Shell scripts and utilities
  - `config/` - Configuration files (Containerfile, mcp.json, etc.)
  - `tests/` - Test scripts
- **Naming** - Use clear, descriptive names for functions and variables
- **Comments** - Add comments for non-obvious logic

## Testing Requirements

Before submitting a pull request, run the integration tests:

```bash
./tests/integration/test-db-integration.sh
```

This requires a running MSSQL server. If you don't have one available, ensure your changes don't break the build:

```bash
./claude-run.sh --build
```

**Note:** Database integration tests verify MSSQL connectivity and operations. These tests require `DB_SERVER`, `DB_USERNAME`, and `DB_PASSWORD` environment variables to be set.

## Build Instructions

To build the Claude Container image:

```bash
./claude-run.sh --build
```

To build without using cache:

```bash
./claude-run.sh --build-no-cache
```

To test your build in an interactive container:

```bash
./claude-run.sh --shell
```

## Development Workflow

1. Make your changes
2. Test locally:
   ```bash
   ./claude-run.sh --build
   ./tests/integration/test-db-integration.sh  # If your changes affect database features
   ```
3. Run the container to verify:
   ```bash
   ./claude-run.sh
   ```
4. Check that existing functionality still works
5. Submit your PR with a clear description

## Questions?

Feel free to open an issue with the `question` label if you need clarification on anything. We're here to help!
