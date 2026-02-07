# Contributing to Agent Orchestrator

Thank you for your interest in contributing to Agent Orchestrator! This document provides guidelines for setting up your development environment and submitting contributions.

## Development Setup

### Prerequisites

- Bash 4.0+ (for lowercase expansion)
- jq (JSON processing)
- Docker (optional, for sandbox testing)
- OpenCode CLI: `npm install -g @anthropic-ai/opencode`
- shellcheck (for linting)

### Initial Setup

```bash
git clone https://github.com/dkapellusch/Agent-Orchestration.git
cd Agent-Orchestration
export PATH="$PWD:$PATH"
opencode auth login
```

### Running Tests

Always run the test suite before submitting changes:

```bash
./tests.sh
```

The test suite covers:
- Core library functions (locking, JSON operations)
- CLI argument parsing
- Completion detection
- Session management
- Cost tracking
- Rate limit detection

## Coding Standards

### Shell Script Style

All shell scripts must follow these standards:

1. **ShellCheck Clean**: All scripts must pass shellcheck with no errors or warnings.
   ```bash
   shellcheck ralph cmd/*.sh lib/*.sh
   ```

2. **Error Handling**: Use `set -euo pipefail` at the top of every script.
   - `-e`: Exit on error
   - `-u`: Exit on undefined variable
   - `-o pipefail`: Fail if any command in a pipeline fails

3. **Quoting**: Always quote variables unless you explicitly need word splitting.
   ```bash
   # Good
   local file="$1"
   echo "$file"

   # Bad
   local file=$1
   echo $file
   ```

4. **Functions**: Use clear, descriptive function names with comments.
   ```bash
   # Acquires a file lock with retry logic
   # Args: $1 = lock directory path
   # Returns: 0 on success, 1 on failure
   acquire_lock() {
       local lockdir="$1"
       # Implementation...
   }
   ```

5. **Indentation**: Use 4 spaces for shell scripts (see `.editorconfig`).

6. **Error Messages**: All errors must go to stderr with consistent formatting.
   ```bash
   echo "Error: Something went wrong" >&2
   ```

### Cross-Platform Compatibility

Code must work on both macOS and Linux:
- Use the cross-platform wrappers in `lib/core.sh` for `stat`, `date`, `timeout`, etc.
- Avoid GNU-specific flags (e.g., use `cp` with existence checks instead of `cp -n`)
- Test on both platforms when possible

## Pull Request Process

### Before Submitting

1. **Run tests**: Ensure `./tests.sh` passes
2. **Run shellcheck**: Fix any linting issues
3. **Test manually**: Try your changes in a real scenario
4. **Update docs**: Update README.md or other docs if needed
5. **Check diffs**: Review your changes for unintended modifications

### PR Guidelines

1. **Title**: Use a clear, descriptive title
   - Good: "Fix race condition in acquire_lock"
   - Bad: "Update core.sh"

2. **Description**: Explain what and why
   - What problem does this solve?
   - What approach did you take?
   - Are there any trade-offs or limitations?

3. **Scope**: Keep PRs focused on a single concern
   - Split large changes into multiple PRs
   - Don't mix refactoring with feature additions

4. **Commits**: Write clear commit messages
   - First line: Brief summary (50 chars or less)
   - Body: Detailed explanation if needed

### CI Checks

All PRs must pass:
- Test suite (`./tests.sh`)
- ShellCheck linting
- Manual review from maintainers

## Issue Reporting

### Bug Reports

Include the following information:

1. **Environment**:
   - OS and version
   - Bash version (`bash --version`)
   - OpenCode version (`opencode --version`)

2. **Steps to Reproduce**:
   - Exact commands you ran
   - Current working directory
   - Relevant configuration

3. **Expected vs Actual**:
   - What you expected to happen
   - What actually happened

4. **Logs**:
   - Include relevant error messages
   - Session logs from `.ralph/{session-id}/`
   - Output from `ralph models` or `ralph stats`

### Feature Requests

Clearly describe:
- The problem you're trying to solve
- Why existing features don't address it
- Proposed solution (optional)

## Code Review

All contributions are reviewed for:
- Correctness and robustness
- Code quality and style
- Test coverage
- Documentation
- Backward compatibility

Reviewers may ask for changes. This is a normal part of the process and helps maintain code quality.

## Getting Help

- Open an issue for questions
- Check existing issues and documentation first
- Be specific about what you're trying to accomplish

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
