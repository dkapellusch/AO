#!/usr/bin/env bash
# install.sh - Install GSD (Get Shit Done) for OpenCode/Claude Code
#
# GSD is a meta-prompting, context engineering and spec-driven development
# system that provides structured workflows for AI-assisted development.
#
# Usage: ./install.sh [--opencode|--claude|--both] [--global|--local]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
RUNTIME="opencode"
SCOPE="global"

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--opencode) RUNTIME="opencode"; shift ;;
		--claude) RUNTIME="claude"; shift ;;
		--both) RUNTIME="both"; shift ;;
		--global) SCOPE="global"; shift ;;
		--local) SCOPE="local"; shift ;;
		-h|--help)
			cat <<EOF
Usage: install.sh [OPTIONS]

Install GSD (Get Shit Done) for AI-assisted development.

Options:
  --opencode    Install for OpenCode (default)
  --claude      Install for Claude Code
  --both        Install for both runtimes
  --global      Install globally (default)
  --local       Install locally to current project
  -h, --help    Show this help

Examples:
  ./install.sh                    # Install for OpenCode globally
  ./install.sh --claude --local   # Install for Claude Code locally
  ./install.sh --both --global    # Install for both runtimes globally
EOF
			exit 0
			;;
		*) echo "Unknown option: $1"; exit 1 ;;
	esac
done

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                  GSD (Get Shit Done) Installer                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Runtime: $RUNTIME"
echo "Scope:   $SCOPE"
echo ""

# Build npx command
NPX_ARGS=("get-shit-done-cc@latest")

case $RUNTIME in
	opencode)
		NPX_ARGS+=("--opencode")
		;;
	claude)
		NPX_ARGS+=("--claude")
		;;
	both)
		NPX_ARGS+=("--both")
		;;
esac

case $SCOPE in
	global)
		NPX_ARGS+=("--global")
		;;
	local)
		NPX_ARGS+=("--local")
		;;
esac

echo "Installing GSD..."
echo "Command: npx ${NPX_ARGS[*]}"
echo ""

# Run installation with properly quoted array expansion
if npx "${NPX_ARGS[@]}"; then
	echo ""
	echo "╔══════════════════════════════════════════════════════════════════╗"
	echo "║                    GSD Installed Successfully                    ║"
	echo "╚══════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Available commands:"
	echo ""
	echo "  Project Setup:"
	echo "    /gsd:map-codebase       Analyze existing codebase"
	echo "    /gsd:new-project        Start new project with requirements"
	echo ""
	echo "  Phase Workflow:"
	echo "    /gsd:discuss-phase [N]  Capture implementation decisions"
	echo "    /gsd:plan-phase [N]     Research + plan + verify"
	echo "    /gsd:execute-phase <N>  Execute tasks in parallel"
	echo "    /gsd:verify-work [N]    User acceptance testing"
	echo ""
	echo "  Quick Tasks:"
	echo "    /gsd:quick              Execute ad-hoc task"
	echo "    /gsd:debug [desc]       Systematic debugging"
	echo ""
	echo "  Progress & Session:"
	echo "    /gsd:progress           Show current status"
	echo "    /gsd:pause-work         Create handoff document"
	echo "    /gsd:resume-work        Resume from handoff"
	echo "    /gsd:help               Show all commands"
	echo ""
	echo "To use with our infrastructure (rate limiting, sandbox):"
	echo "  cd $SCRIPT_DIR/.."
	echo "  ./gsd/gsd-runner [--sandbox] [--tier medium] /gsd:new-project"
	echo ""
else
	echo ""
	echo "Error: GSD installation failed"
	exit 1
fi
