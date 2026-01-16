# Security Policy

## Supported Versions

Only the latest version of Claude Container is supported for security updates.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

## Security Focus

Claude Container is a security-focused Podman container designed for isolated environments. Key security features include:

- **Network Isolation**: Whitelist-based firewall (iptables) that restricts outbound connections to approved services only
- **Restricted Filesystem Access**: MCP Filesystem operations are confined to `/workspace`
- **Resource Limits**: Configurable CPU and memory constraints
- **Non-root User**: Container runs as non-root `claude` user

## Reporting Vulnerabilities

Security vulnerabilities should **not** be disclosed publicly. Instead, please report them through one of these channels:

### Option 1: GitHub Security Advisory (Recommended)
Use GitHub's private vulnerability reporting feature:
1. Go to the repository Security tab
2. Click "Report a vulnerability"
3. Provide details of the vulnerability

### Option 2: Email
Email security reports to the maintainer:
- **Contact**: [@aubi-one-david](https://github.com/aubi-one-david)

## Response Timeline

As a small open source project, we aim to:
- **Acknowledge** reports within 7 days
- **Assess** and develop a fix within 14 days
- **Release** a patched version as soon as feasible

Response times may vary based on severity and complexity of the issue.

## Security Considerations

When using Claude Container, be aware of:
- Always keep `ANTHROPIC_API_KEY` and other credentials secure
- Use `CLAUDE_SHARE_AUTH` carefully to avoid sharing authentication tokens
- Review firewall whitelist rules in `scripts/init-firewall.sh` if accessing additional services
- Run only trusted images and verify container integrity
