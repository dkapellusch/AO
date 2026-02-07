#!/usr/bin/env bash
# stream-formatter.sh - Format Claude Code stream-json output for human readability
# Reads JSON lines from stdin, outputs colored formatted text
#
# Environment:
#   RALPH_VERBOSE=true  - Show full output without truncation
#   NO_COLOR=1          - Disable color output (https://no-color.org/)

# Truncation limits (when not verbose)
THINKING_LINES=3
TOOL_INPUT_CHARS=200
TOOL_RESULT_CHARS=300
TEXT_CHARS=0  # 0 = no limit

# Check verbose mode
if [[ "${RALPH_VERBOSE:-false}" == "true" ]]; then
    THINKING_LINES=0
    TOOL_INPUT_CHARS=0
    TOOL_RESULT_CHARS=0
fi

# Color support - respect NO_COLOR standard
if [[ -n "${NO_COLOR:-}" ]]; then
    RST="" BOLD="" DIM="" ITAL=""
    RED="" GRN="" YEL="" BLU="" MAG="" CYN="" GRY=""
else
    RST=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m' ITAL=$'\033[3m'
    RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' BLU=$'\033[34m'
    MAG=$'\033[35m' CYN=$'\033[36m' GRY=$'\033[90m'
fi

# Extract a simple string value from JSON without forking jq
# Usage: extract_json_string "$json" "key"
# Returns empty string if not found
extract_json_string() {
    local json="$1" key="$2"
    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Fast type extraction without forking jq
    case "$line" in
        *'"type":"assistant"'*|*'"type": "assistant"'*) type="assistant" ;;
        *'"type":"tool_result"'*|*'"type": "tool_result"'*) type="tool_result" ;;
        *'"type":"user"'*|*'"type": "user"'*) type="user" ;;
        *'"type":"result"'*|*'"type": "result"'*) type="result" ;;
        *) continue ;;
    esac

    case "$type" in
        assistant)
            content=$(jq -r \
                --arg rst "$RST" --arg bold "$BOLD" --arg dim "$DIM" --arg ital "$ITAL" \
                --arg cyn "$CYN" --arg yel "$YEL" --arg red "$RED" \
                --arg mag "$MAG" --arg blu "$BLU" --arg gry "$GRY" \
                --argjson think_lines "$THINKING_LINES" \
                --argjson tool_chars "$TOOL_INPUT_CHARS" \
                '
                # Shorten file paths to last 3 segments
                def short_path:
                    if . == null or . == "" then "?"
                    elif $tool_chars == 0 then .
                    else split("/") |
                        if length > 3 then "…/" + (.[-3:] | join("/"))
                        else join("/") end
                    end;

                # Clean MCP tool names: mcp__foo__bar → foo/bar
                def display_name:
                    if startswith("mcp__") then .[5:] | gsub("__"; "/")
                    else . end;

                .message.content[]? |
                if .type == "thinking" then
                    if $think_lines == 0 then
                        $dim + $ital + "💭 " + (.thinking // "") + $rst
                    else
                        $dim + $ital + "💭 " + (
                            .thinking // "" | split("\n") |
                            if length > $think_lines then
                                .[0:$think_lines] | join("\n   ") | . + "…"
                            else join("\n   ") end
                        ) + $rst
                    end
                elif .type == "text" then
                    .text // ""
                elif .type == "tool_use" then
                    # Icon by tool name
                    ({"Read":"📖","Grep":"🔍","Glob":"📂","Edit":"✏️ ","Write":"📝",
                      "Bash":"⚡","Task":"🤖","WebFetch":"🌐","WebSearch":"🌐",
                      "LSP":"🔗","NotebookEdit":"📓"}[.name] // "🔧") as $icon |
                    # Color by tool category
                    (if .name == "Read" or .name == "Glob" or .name == "Grep" or .name == "LSP" then $cyn
                     elif .name == "Edit" or .name == "Write" or .name == "NotebookEdit" then $yel
                     elif .name == "Bash" then $red
                     elif .name == "Task" then $mag
                     elif .name == "WebFetch" or .name == "WebSearch" then $blu
                     else "" end) as $color |
                    # Extract meaningful detail per tool type
                    (if .name == "Read" then
                        (.input.file_path // "" | short_path)
                        + (if .input.offset then
                            " :" + (.input.offset | tostring)
                            + (if .input.limit then "-" + ((.input.offset + .input.limit) | tostring) else "" end)
                          else "" end)
                     elif .name == "Grep" then
                        "/" + (.input.pattern // "") + "/"
                        + (if .input.glob then " {" + .input.glob + "}" else "" end)
                        + (if .input.path then "  " + (.input.path | short_path) else "" end)
                        + (if .input.output_mode and .input.output_mode != "files_with_matches" then
                            " [" + .input.output_mode + "]" else "" end)
                     elif .name == "Glob" then
                        (.input.pattern // "")
                        + (if .input.path then "  " + (.input.path | short_path) else "" end)
                     elif .name == "Edit" then
                        (.input.file_path // "" | short_path)
                     elif .name == "Write" then
                        (.input.file_path // "" | short_path)
                     elif .name == "Bash" then
                        (.input.command // "" | gsub("\n"; " ") |
                            .[0:if $tool_chars > 0 then $tool_chars else 999999 end])
                        + (if $tool_chars > 0 and ((.input.command // "") | length) > $tool_chars then "…" else "" end)
                     elif .name == "Task" then
                        (.input.description // "" | .[0:60])
                     elif .name == "WebFetch" then
                        (.input.url // "")
                     elif .name == "WebSearch" then
                        (.input.query // "")
                     else
                        (.input | tostring |
                            .[0:if $tool_chars > 0 then $tool_chars else 999999 end])
                        + (if $tool_chars > 0 and ((.input | tostring) | length) > $tool_chars then "…" else "" end)
                     end) as $detail |
                    $color + $icon + " " + $bold + (.name | display_name) + $rst + "  " + $gry + $detail + $rst
                else empty end
                ' <<< "$line" 2>/dev/null)
            [[ -n "$content" ]] && echo "$content"
            ;;
        tool_result)
            if [[ $TOOL_RESULT_CHARS -eq 0 ]]; then
                result=$(jq -r \
                    --arg rst "$RST" --arg red "$RED" --arg gry "$GRY" '
                    if .is_error then
                        $red + "   ⚠ " + (.content // "" | tostring) + $rst
                    else
                        $gry + "   " + (.content // "" | tostring) + $rst
                    end' <<< "$line" 2>/dev/null)
            else
                result=$(jq -r \
                    --arg rst "$RST" --arg red "$RED" --arg gry "$GRY" \
                    --argjson chars "$TOOL_RESULT_CHARS" '
                    if .is_error then
                        $red + "   ⚠ " + (.content // "" | tostring | .[0:$chars]) +
                        (if ((.content // "" | tostring) | length) > $chars then "…" else "" end) + $rst
                    else
                        $gry + "   " + (.content // "" | tostring | .[0:$chars]) +
                        (if ((.content // "" | tostring) | length) > $chars then "…" else "" end) + $rst
                    end' <<< "$line" 2>/dev/null)
            fi
            [[ -n "$result" ]] && echo "$result"
            ;;
        user)
            # Tool results come as user messages
            if [[ $TOOL_RESULT_CHARS -eq 0 ]]; then
                content=$(jq -r \
                    --arg rst "$RST" --arg red "$RED" --arg gry "$GRY" '
                    .message.content[]? |
                    if .type == "tool_result" then
                        if .is_error then
                            $red + "   ⚠ " + (.content // "" | tostring) + $rst
                        else
                            $gry + "   " + (.content // "" | tostring) + $rst
                        end
                    else empty end' <<< "$line" 2>/dev/null)
            else
                content=$(jq -r \
                    --arg rst "$RST" --arg red "$RED" --arg gry "$GRY" \
                    --argjson chars "$TOOL_RESULT_CHARS" '
                    .message.content[]? |
                    if .type == "tool_result" then
                        if .is_error then
                            $red + "   ⚠ " + (.content // "" | tostring | .[0:$chars]) +
                            (if ((.content // "" | tostring) | length) > $chars then "…" else "" end) + $rst
                        else
                            $gry + "   " + (.content // "" | tostring | .[0:$chars]) +
                            (if ((.content // "" | tostring) | length) > $chars then "…" else "" end) + $rst
                        end
                    else empty end' <<< "$line" 2>/dev/null)
            fi
            [[ -n "$content" ]] && echo "$content"
            ;;
        result)
            # Single jq call for all result fields
            result_info=$(jq -r '[.subtype // "", .total_cost_usd // 0, .duration_ms // 0] | @tsv' <<< "$line" 2>/dev/null) || continue
            IFS=$'\t' read -r subtype cost duration <<< "$result_info"
            if [[ "$subtype" == "success" ]]; then
                echo ""
                echo "${GRN}${BOLD}✅ Done${RST} ${GRY}(${duration}ms, \$${cost})${RST}"
            fi
            ;;
    esac
done
:
