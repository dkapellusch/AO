#!/usr/bin/env bash
# agents.sh - Shared agent management for agent-orchestrator
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/agents.sh"
#
# Provides:
# - Shared agent directory access
# - Agent synchronization to working directories
# - Agent validation
# - Agent listing and inspection

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# ============================================================================
# Agent Directory Access
# ============================================================================

# Get path to shared agents directory
# Usage: shared_agents_dir=$(get_shared_agents_dir)
get_shared_agents_dir() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	echo "$script_dir/agents"
}

# ============================================================================
# Agent Validation
# ============================================================================

# Validate agent definition file
# Usage: validate_agent "agent.md"
# Returns 0 if valid, 1 if invalid (with error message to stderr)
validate_agent() {
	local agent_file="$1"

	if [[ ! -f "$agent_file" ]]; then
		echo "Error: Agent file not found: $agent_file" >&2
		return 1
	fi

	# Check YAML frontmatter exists
	if ! head -1 "$agent_file" | grep -q "^---"; then
		echo "Error: Missing YAML frontmatter in $agent_file" >&2
		return 1
	fi

	# Check required fields
	if ! grep -q "^description:" "$agent_file"; then
		echo "Error: Missing 'description' field in $agent_file" >&2
		return 1
	fi

	if ! grep -q "^mode:" "$agent_file"; then
		echo "Error: Missing 'mode' field in $agent_file" >&2
		return 1
	fi

	# Check mode is valid
	local mode
	mode=$(grep "^mode:" "$agent_file" | awk '{print $2}')
	if [[ "$mode" != "primary" && "$mode" != "subagent" ]]; then
		echo "Error: Invalid mode '$mode' in $agent_file (must be 'primary' or 'subagent')" >&2
		return 1
	fi

	return 0
}

# Validate all agents in shared agents directory
# Usage: validate_all_agents
# Returns 0 if all valid, 1 if any invalid
validate_all_agents() {
	local shared_dir
	shared_dir=$(get_shared_agents_dir)
	local all_valid=0

	if [[ ! -d "$shared_dir" ]]; then
		echo "Error: Shared agents directory not found: $shared_dir" >&2
		return 1
	fi

	for agent_file in "$shared_dir"/*.md; do
		if [[ ! -f "$agent_file" ]]; then
			continue
		fi
		if ! validate_agent "$agent_file"; then
			all_valid=1
		fi
	done

	return $all_valid
}

# ============================================================================
# Agent Synchronization
# ============================================================================

# Sync shared agents to a target directory
# Usage: sync_agents_to "/path/to/target"
# Only copies agents that don't already exist (preserves project overrides)
sync_agents_to() {
	local target_dir="$1"
	local shared_dir
	shared_dir=$(get_shared_agents_dir)

	if [[ ! -d "$shared_dir" ]]; then
		echo "WARNING: Shared agents directory not found: $shared_dir" >&2
		return 0
	fi

	mkdir -p "$target_dir"

	# Copy all shared agents (cp -n = no-clobber, preserves existing)
	local synced_count=0
	local skipped_count=0

	for agent_file in "$shared_dir"/*.md; do
		if [[ ! -f "$agent_file" ]]; then
			continue
		fi

		local agent_name
		agent_name=$(basename "$agent_file")

		# Check if target already has this agent
		if [[ -f "$target_dir/$agent_name" ]]; then
			skipped_count=$((skipped_count + 1))
		else
			cp "$agent_file" "$target_dir/$agent_name"
			synced_count=$((synced_count + 1))
		fi
	done

	if [[ $synced_count -gt 0 ]]; then
		echo "Synced $synced_count shared agent(s) to $target_dir" >&2
	fi
	if [[ $skipped_count -gt 0 ]]; then
		echo "Skipped $skipped_count existing agent(s) (project overrides preserved)" >&2
	fi

	return 0
}

# Ensure agents are available in working directory
# Usage: ensure_agents "/path/to/working/dir"
# Creates .opencode/agents if needed and syncs shared agents
ensure_agents() {
	local working_dir="$1"
	local agents_dir="$working_dir/.opencode/agents"

	mkdir -p "$agents_dir"
	sync_agents_to "$agents_dir"
}

# ============================================================================
# Agent Listing and Inspection
# ============================================================================

# List all available shared agents with descriptions
# Usage: list_agents
# Output format: "name - description"
list_agents() {
	local shared_dir
	shared_dir=$(get_shared_agents_dir)

	if [[ ! -d "$shared_dir" ]]; then
		echo "Error: Shared agents directory not found: $shared_dir" >&2
		return 1
	fi

	for agent_file in "$shared_dir"/*.md; do
		if [[ ! -f "$agent_file" ]]; then
			continue
		fi

		local name
		name=$(basename "$agent_file" .md)

		local desc
		desc=$(grep -m1 "^description:" "$agent_file" | sed 's/^description: *//; s/"//g; s/^'\''//; s/'\''$//')

		printf "%-20s %s\n" "$name" "$desc"
	done
}

# Get agent info as JSON
# Usage: get_agent_info "yolo"
# Returns JSON with name, description, mode, tools, permissions
get_agent_info() {
	local agent_name="$1"
	local shared_dir
	shared_dir=$(get_shared_agents_dir)
	local agent_file="$shared_dir/${agent_name}.md"

	if [[ ! -f "$agent_file" ]]; then
		jq -n --arg name "$agent_name" '{"error": ("Agent not found: " + $name)}'
		return 1
	fi

	local frontmatter
	frontmatter=$(awk '/^---$/{flag=!flag; next} flag' "$agent_file")

	local description mode model temperature max_steps
	description=$(echo "$frontmatter" | grep "^description:" | sed 's/^description: *//; s/"//g; s/^'\''//; s/'\''$//' || true)
	mode=$(echo "$frontmatter" | grep "^mode:" | awk '{print $2}' || true)
	model=$(echo "$frontmatter" | grep "^model:" | awk '{print $2}' || true)
	temperature=$(echo "$frontmatter" | grep "^temperature:" | awk '{print $2}' || true)
	max_steps=$(echo "$frontmatter" | grep "^maxSteps:" | awk '{print $2}' || true)

	jq -n \
		--arg name "$agent_name" \
		--arg desc "$description" \
		--arg mode "$mode" \
		--arg model "${model:-not specified}" \
		--arg temp "${temperature:-default}" \
		--arg steps "${max_steps:-default}" \
		'{name: $name, description: $desc, mode: $mode, model: $model, temperature: $temp, maxSteps: $steps}'

	return 0
}

# Show detailed agent information
# Usage: show_agent "yolo"
show_agent() {
	local agent_name="$1"
	local shared_dir
	shared_dir=$(get_shared_agents_dir)
	local agent_file="$shared_dir/${agent_name}.md"

	if [[ ! -f "$agent_file" ]]; then
		echo "Error: Agent not found: $agent_name" >&2
		return 1
	fi

	echo "=== Agent: $agent_name ==="
	echo ""

	# Extract and display frontmatter in readable format
	echo "Configuration:"
	awk '/^---$/{flag=!flag; next} flag' "$agent_file" | sed 's/^/  /'

	echo ""
	echo "Content:"
	awk '/^---$/{count++; next} count>=2' "$agent_file" | head -20
	echo ""
	echo "(Use 'cat' to see full content)"
}

# ============================================================================
# Agent Creation Helper
# ============================================================================

# Create a new shared agent from template
# Usage: create_agent "name" "description" "mode" [tools]
create_agent() {
	local name="$1"
	local description="$2"
	local mode="$3"
	local tools="${4:-read,grep,glob}"

	if [[ -z "$name" || -z "$description" || -z "$mode" ]]; then
		echo "Error: Usage: create_agent NAME DESCRIPTION MODE [TOOLS]" >&2
		return 1
	fi

	if [[ "$mode" != "primary" && "$mode" != "subagent" ]]; then
		echo "Error: Mode must be 'primary' or 'subagent'" >&2
		return 1
	fi

	local shared_dir
	shared_dir=$(get_shared_agents_dir)
	local agent_file="$shared_dir/${name}.md"

	if [[ -f "$agent_file" ]]; then
		echo "Error: Agent already exists: $agent_file" >&2
		return 1
	fi

	# Parse tools into YAML
	local tools_yaml=""
	IFS=',' read -ra TOOL_ARRAY <<<"$tools"
	for tool in "${TOOL_ARRAY[@]}"; do
		tool=$(echo "$tool" | xargs) # trim whitespace
		tools_yaml+="  ${tool}: true"$'\n'
	done

	# Create agent file (use regular heredoc without - to preserve exact formatting)
	cat >"$agent_file" <<EOF
---
description: "$description"
mode: $mode
tools:
$tools_yaml---

# $name Agent

[Add your agent instructions here]

## Purpose

$description

## Instructions

[Add specific instructions for this agent]
EOF

	echo "Created new agent: $agent_file"
	echo "Edit the file to add detailed instructions."
	return 0
}

# ============================================================================
# Initialization
# ============================================================================

# Ensure shared agents directory exists
_init_agents_dir() {
	local shared_dir
	shared_dir=$(get_shared_agents_dir)

	if [[ ! -d "$shared_dir" ]]; then
		mkdir -p "$shared_dir"
	fi
}

# Run initialization
_init_agents_dir
