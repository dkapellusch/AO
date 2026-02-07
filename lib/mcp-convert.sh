#!/usr/bin/env bash
# mcp-convert.sh - Convert between MCP config formats
# Supports: Claude Code (.mcp.json) <-> OpenCode (opencode.json)

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# Convert Claude Code .mcp.json to OpenCode mcp config format
# Usage: convert_mcp_to_opencode "/path/to/.mcp.json"
# Output: JSON object suitable for merging into opencode.json
convert_mcp_to_opencode() {
    local mcp_json="$1"

    if [[ ! -f "$mcp_json" ]]; then
        echo "{}"
        return 1
    fi

    # Convert mcpServers format to OpenCode mcp format
    # Claude local: {"mcpServers": {"name": {"command": "cmd", "args": ["a","b"], "env": {...}}}}
    # Claude remote: {"mcpServers": {"name": {"type": "http", "url": "...", "headers": {...}}}}
    # OpenCode local: {"mcp": {"name": {"type": "local", "command": ["cmd","a","b"], "environment": {...}}}}
    # OpenCode remote: {"mcp": {"name": {"type": "remote", "url": "...", "headers": {...}}}}
    jq '
    if .mcpServers then
        {
            mcp: (
                .mcpServers | to_entries | map({
                    key: .key,
                    value: (
                        if .value.type == "http" or .value.url then
                            # Remote/HTTP server
                            {
                                type: "remote",
                                url: .value.url,
                                enabled: true
                            } + (
                                if .value.headers then
                                    {headers: .value.headers}
                                else
                                    {}
                                end
                            )
                        else
                            # Local/stdio server
                            {
                                type: "local",
                                command: (
                                    if .value.args then
                                        [.value.command] + .value.args
                                    else
                                        [.value.command]
                                    end
                                ),
                                enabled: true
                            } + (
                                if .value.env then
                                    {environment: .value.env}
                                else
                                    {}
                                end
                            )
                        end
                    )
                }) | from_entries
            )
        }
    else
        # Already in some other format or empty
        {}
    end
    ' "$mcp_json" 2>/dev/null || echo "{}"
}

# Merge MCP config into existing OpenCode config
# Usage: merge_opencode_config "/path/to/base/opencode.json" "/path/to/.mcp.json" > merged.json
merge_opencode_config() {
    local base_config="$1"
    local mcp_json="$2"

    local mcp_converted
    mcp_converted=$(convert_mcp_to_opencode "$mcp_json")

    if [[ -f "$base_config" ]]; then
        # Merge: base config + converted MCP config
        jq -s '.[0] * .[1]' "$base_config" <(echo "$mcp_converted") 2>/dev/null
    else
        # Just output converted config with schema
        echo "$mcp_converted" | jq '. + {"$schema": "https://opencode.ai/config.json"}' 2>/dev/null
    fi
}

# Create OpenCode config with MCP servers for container use
# Usage: create_opencode_mcp_config "/path/to/.mcp.json" "/output/opencode.json"
create_opencode_mcp_config() {
    local mcp_json="$1"
    local output_file="$2"

    local converted
    converted=$(convert_mcp_to_opencode "$mcp_json")

    # Add schema and write
    echo "$converted" | jq '. + {"$schema": "https://opencode.ai/config.json"}' > "$output_file" 2>/dev/null
}

# Convenience function: ensure OpenCode MCP config exists for a Claude MCP config
# Returns path to temp file (caller must clean up) or empty string if no MCP config
# Usage: OPENCODE_MCP_CONFIG_FILE=$(ensure_opencode_mcp_config "$MCP_CONFIG")
ensure_opencode_mcp_config() {
    local mcp_config="$1"

    if [[ -z "$mcp_config" ]] || [[ ! -f "$mcp_config" ]]; then
        echo ""
        return 0
    fi

    local temp_file
    temp_file=$(mktemp -t "opencode-mcp-XXXXXX.json")
    create_opencode_mcp_config "$mcp_config" "$temp_file"
    echo "$temp_file"
}

# If run directly, convert the provided file
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <mcp.json> [base-opencode.json]"
        echo ""
        echo "Converts Claude Code .mcp.json to OpenCode format"
        exit 1
    fi

    if [[ $# -ge 2 ]]; then
        merge_opencode_config "$2" "$1"
    else
        convert_mcp_to_opencode "$1"
    fi
fi
