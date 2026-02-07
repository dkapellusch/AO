#!/usr/bin/env bash
# agents.sh - CLI tool for managing shared agents
# Invoked via: ralph agents [COMMAND]
#
# Usage:
#   ralph agents list                    List all shared agents
#   ralph agents show AGENT              Show agent details
#   ralph agents info AGENT              Get agent info as JSON
#   ralph agents sync [--dir DIR]        Sync agents to directory
#   ralph agents validate                Validate all agents
#   ralph agents create NAME DESC MODE   Create new agent

# Source the agents library
source "$RALPH_ROOT/lib/agents.sh"

# ============================================================================
# CLI Functions
# ============================================================================

show_usage() {
	cat <<-'EOF'
		ralph agents - Shared Agent Management

		Usage:
		  ralph agents list                    List all shared agents
		  ralph agents show AGENT              Show detailed agent info
		  ralph agents info AGENT              Get agent info as JSON
		  ralph agents sync [--dir DIR]        Sync agents to directory
		  ralph agents validate                Validate all agent definitions
		  ralph agents create NAME DESC MODE [TOOLS]
		                                       Create new agent

		Commands:
		  list        List all available shared agents with descriptions
		  show        Display detailed information about a specific agent
		  info        Get agent configuration as JSON
		  sync        Sync shared agents to a directory (.opencode/agents)
		  validate    Validate all agent definitions (check syntax)
		  create      Create a new shared agent from template

		Examples:
		  # List all agents
		  ralph agents list

		  # Show yolo agent details
		  ralph agents show yolo

		  # Sync agents to current project
		  ralph agents sync --dir ~/project

		  # Validate all agents
		  ralph agents validate

		  # Create new agent
		  ralph agents create fixer "Fix lint errors" primary "read,write,edit,bash"

		Agent Modes:
		  primary     Main agent that can run independently
		  subagent    Helper agent spawned by other agents

		Options:
		  --dir DIR   Target directory for sync (creates .opencode/agents)
		  --help      Show this help message
	EOF
}

cmd_list() {
	echo "Available Shared Agents:"
	echo ""
	list_agents
}

cmd_show() {
	local agent_name="$1"

	if [[ -z "$agent_name" ]]; then
		echo "ERROR: Agent name required" >&2
		echo "Usage: ralph agents show AGENT" >&2
		return 1
	fi

	show_agent "$agent_name"
}

cmd_info() {
	local agent_name="$1"

	if [[ -z "$agent_name" ]]; then
		echo "ERROR: Agent name required" >&2
		echo "Usage: ralph agents info AGENT" >&2
		return 1
	fi

	get_agent_info "$agent_name"
}

cmd_sync() {
	local target_dir="$1"

	if [[ -z "$target_dir" ]]; then
		target_dir="$(pwd)"
	fi

	echo "Syncing shared agents to: $target_dir/.opencode/agents"
	ensure_agents "$target_dir"
	echo "Done."
}

cmd_validate() {
	echo "Validating shared agents..."
	echo ""

	local shared_dir
	shared_dir=$(get_shared_agents_dir)
	local valid_count=0
	local invalid_count=0

	for agent_file in "$shared_dir"/*.md; do
		if [[ ! -f "$agent_file" ]]; then
			continue
		fi

		local agent_name
		agent_name=$(basename "$agent_file" .md)

		if validate_agent "$agent_file"; then
			echo "  $agent_name"
			valid_count=$((valid_count + 1))
		else
			echo "X $agent_name"
			invalid_count=$((invalid_count + 1))
		fi
	done

	echo ""
	echo "Results: $valid_count valid, $invalid_count invalid"

	if [[ $invalid_count -gt 0 ]]; then
		return 1
	fi

	return 0
}

cmd_create() {
	local name="$1"
	local description="$2"
	local mode="$3"
	local tools="${4:-read,grep,glob}"

	if [[ -z "$name" || -z "$description" || -z "$mode" ]]; then
		echo "ERROR: NAME, DESCRIPTION, and MODE required" >&2
		echo "Usage: ralph agents create NAME DESCRIPTION MODE [TOOLS]" >&2
		echo "Example: ralph agents create fixer 'Fix lint errors' primary 'read,write,edit'" >&2
		return 1
	fi

	create_agent "$name" "$description" "$mode" "$tools"
}

# ============================================================================
# Main
# ============================================================================

if [[ $# -eq 0 ]]; then
	show_usage
	exit 0
fi

command="$1"
shift

case "$command" in
list)
	cmd_list "$@"
	;;
show)
	cmd_show "$@"
	;;
info)
	cmd_info "$@"
	;;
sync)
	# Parse --dir option
	target_dir=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dir)
			target_dir="$2"
			shift 2
			;;
		*)
			target_dir="$1"
			shift
			;;
		esac
	done
	cmd_sync "$target_dir"
	;;
validate)
	cmd_validate "$@"
	;;
create)
	cmd_create "$@"
	;;
--help | -h | help)
	show_usage
	;;
*)
	echo "ERROR: Unknown command: $command" >&2
	echo "" >&2
	show_usage >&2
	exit 1
	;;
esac
