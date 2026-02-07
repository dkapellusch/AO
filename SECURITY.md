# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Agent Orchestration, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email the maintainers directly or use [GitHub's private vulnerability reporting](https://github.com/dkapellusch/Agent-Orchestration/security/advisories/new).

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and aim to provide a fix or mitigation within 7 days for critical issues.

## Security Considerations

Agent Orchestration runs AI coding agents that can execute arbitrary commands on your system. Please be aware of the following:

### Sandbox Modes

- **`--sandbox anthropic`** (recommended): Uses Anthropic's sandbox runtime for filesystem and network isolation
- **`--sandbox docker`**: Runs agents in a Docker container with controlled volume mounts
- **`--sandbox none`** (default): No isolation - the agent has the same permissions as your user

### Sensitive Path Protection

When using Docker sandbox mode, the following directories are blocked from being mounted:
- `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config/gcloud`
- `/etc`, `/root`, `/var/run/docker.sock`

### API Key Handling

- API keys are passed to containers via temporary env files with `chmod 600`, not command-line arguments
- Keys are never logged or written to session state files
- OAuth tokens extracted from the macOS keychain are handled in-memory

### Best Practices

1. Use `--sandbox anthropic` or `--sandbox docker` for untrusted tasks
2. Set `--budget` limits to prevent cost overruns
3. Review agent output before applying changes to production code
4. Keep your API keys in environment variables, not in config files tracked by git

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | Yes |
| Older commits | Best effort |
