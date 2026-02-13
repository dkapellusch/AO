# Agent Orchestrator

Run AI coding agents in a loop until the job is done. Handles rate limits, model fallbacks, cost tracking, and sandboxing so you don't have to.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dkapellusch/Agent-Orchestration/main/install.sh | bash
```

Then restart your terminal and authenticate:

```bash
opencode auth login    # For OpenCode (Gemini, Claude, GPT)
# and/or
claude                 # For Claude Code
```

<details>
<summary>Manual install</summary>

```bash
git clone https://github.com/dkapellusch/Agent-Orchestration.git ~/agent-orchestration
export PATH="$HOME/agent-orchestration:$PATH"  # Add to ~/.zshrc or ~/.bashrc
```

</details>

See [INSTALLATION.md](INSTALLATION.md) for full setup details.

## Usage

```bash
cd ~/my-project

# Simple task
ao "Fix all lint errors"

# With guardrails
ao "Fix all lint errors" --max 10 --budget 2.00

# Use Claude Code instead of OpenCode
ao "Fix all lint errors" --agent cc
```

### Common Patterns

```bash
# Thorough cleanup: fresh context each iteration, sandboxed, min 5 passes
ao "Address all issues found in this repo" \
  --agent cc --min 5 --reset 1 --max 20 --sandbox docker

# Feature from spec: validate completion with a second agent
ao --file feature-spec.md \
  --tier high --max 30 --budget 10.00 --completion-mode validate

# Quick fix: cheap model, bail fast
ao "Fix the null pointer in src/auth/login.ts" \
  --tier low --max 3

# Overnight run: infinite iterations, budget is the hard stop
ao "Refactor all database queries to use the new ORM" \
  --max 0 --reset 3 --budget 25.00 --sandbox anthropic

# Resume a previous session
ao --session swift-fox-runs

# Inject context into a running session from another terminal
ao --add-context "Focus on the edge case where user.email is null" \
  --session swift-fox-runs

# Target a specific model
ao "Optimize the hot path in src/engine.ts" \
  --model anthropic/claude-opus-4-5 --max 10

# Parallel projects (rate limiting is shared across sessions)
ao "Fix lint errors" --dir ~/project-a --budget 3.00 &
ao "Add unit tests" --dir ~/project-b --budget 5.00 &
wait
```

### GSD Mode (Get Shit Done)

Phase-based development with parallel task execution:

```bash
ao -m gsd new                        # Create project spec
ao -m gsd plan 1                     # Plan phase 1
ao -m gsd execute 1 --tier high      # Execute tasks in parallel
ao -m gsd verify 1                   # Verify results
```

Other GSD commands: `map` (analyze code), `quick` (ad-hoc task), `debug` (systematic debugging).

## How It Works

1. You give `ao` a prompt (or a `--file` with a spec)
2. It picks a model from your chosen `--tier`, respecting rate limits and concurrency
3. The agent works on your codebase, tracking progress in a state file
4. If it's not done, the loop continues with the next iteration
5. When the agent outputs `<promise>COMPLETE</promise>`, the loop stops

**Key behaviors:**
- **Rate limit handling** -- detects 429s, cools down, falls back through tiers (high -> medium -> low)
- **Struggle detection** -- notices repeated errors, no file changes, or short iterations and escalates models
- **Cost tracking** -- per-iteration and cumulative cost display, hard budget stops
- **State reset** -- context resets every N iterations (default 5) to prevent stale reasoning
- **Sessions** -- each run gets a unique ID (e.g., `swift-fox-runs`) for resume, status checks, and context injection

## Commands

| Command | Description |
|---------|-------------|
| `ao` / `ralph loop` | Run the iterative agent loop |
| `ralph models` | Show models and rate-limit status |
| `ralph cost` | Cost reporting (`--days 7 --models` for breakdown) |
| `ralph stats` | Session statistics |
| `ralph cleanup` | Clean old sessions (`--days 7`) |
| `ralph agents` | Manage shared agent definitions |

Run `ao --help` for the full options reference.

## Model Tiers

Models accessed via [OpenCode](https://github.com/opencode-ai/opencode) with OAuth (no API keys needed).

| Tier | Models | Use Case |
|------|--------|----------|
| **high** | Opus, Gemini Pro | Complex reasoning |
| **medium** | Sonnet, Gemini Flash | Standard coding |
| **low** | Haiku, Gemini Flash | Quick/cheap tasks |

Concurrency limits and tier composition are configured in `config/models.json`.

## Sandboxing

```bash
ao "Task" --sandbox auto         # Auto-detect best available
ao "Task" --sandbox anthropic    # Lightweight (recommended)
ao "Task" --sandbox docker       # Heavy isolation
ao "Task" --sandbox none         # Direct host execution

# Grant additional write paths
ao "Generate docs" --sandbox anthropic --allow-write ~/docs
```

Anthropic sandbox: `npm install -g @anthropic-ai/sandbox-runtime`.
Docker sandbox: `./setup/sandbox.sh` (one-time setup).

Network and filesystem allowlists are in `config/sandbox.json`.

## Shared Agents

Built-in agent definitions in `agents/`:

| Agent | Purpose |
|-------|---------|
| `yolo` | Full autonomous execution |
| `explorer` | Read-only codebase exploration |
| `reviewer` | Code review |
| `fixer` | Fix lint/type/test errors |
| `planner` | Implementation planning |

```bash
ralph agents list                  # List all
ralph agents sync --dir ~/project  # Sync to project
```

Agents are auto-synced before every `ao` / `ralph loop` run.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Not authenticated" | `opencode auth login` |
| "All models rate-limited" | Wait for cooldown or add models to `config/models.json` |
| "Docker not running" | Start Docker Desktop |
| "Anthropic sandbox not found" | `npm install -g @anthropic-ai/sandbox-runtime` |
| Session stuck | `ralph loop --status --session {id}` to check struggle indicators |

## Requirements

- **bash 4.0+**, **jq**, **[OpenCode CLI](https://github.com/opencode-ai/opencode)**
- Optional: Docker, Node.js 18+, flock (macOS: `brew install flock`)

## Acknowledgements

- [Everything is a ralph loop](https://ghuntley.com/loop/) / [Ralph as a "software engineer"](https://ghuntley.com/ralph/) -- Geoff Huntley
- [Get Shit Done (GSD)](https://github.com/glittercowboy/get-shit-done) -- spec-driven development for Claude Code
- [OpenCode](https://opencode.ai/) -- open source AI coding agent
- [Claude Code](https://github.com/anthropics/claude-code) -- Anthropic's agentic coding tool

## License

MIT -- See [LICENSE](LICENSE)

---

[INSTALLATION.md](INSTALLATION.md) | [CONTRIBUTING.md](CONTRIBUTING.md) | [SECURITY.md](SECURITY.md) | [CLAUDE.md](CLAUDE.md)
