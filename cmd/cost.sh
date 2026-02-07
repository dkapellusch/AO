#!/usr/bin/env bash
# cost.sh - Cost reporting wrapper for OpenCode with aggregation
# Invoked via: ralph cost [command] [options]

source "$RALPH_ROOT/lib/cost.sh"

usage() {
    cat <<EOF
Usage: ralph cost [command] [options]

Commands:
  (no command)          Show overall stats (wraps opencode stats)
  session <id> [dir]    Show cost for a specific ralph-loop session
  daily [date]          Show costs for a specific date (default: today)
  by-date [--days N]    Show costs aggregated by date
  by-spec [--days N]    Show costs aggregated by spec/task
  by-project [--days N] Show costs aggregated by project

Options:
  --days N          Number of days to look back (default: 30)
  --models          Show model statistics (passthrough to opencode stats)

Examples:
  ralph cost                        # Overall OpenCode stats
  ralph cost daily                  # Today's spending
  ralph cost daily 2025-01-28       # Specific date
  ralph cost by-date --days 7       # Last week by date
  ralph cost by-spec --days 30      # Last month by spec
  ralph cost by-project             # By project directory
  ralph cost session swift-fox-runs # Specific ralph session
EOF
}

# Parse --days flag
parse_days() {
    local days=30
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days) days="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo "$days"
}

cmd_daily() {
    local target_date="${1:-$(date +%Y-%m-%d)}"

    echo ""
    echo "Daily Cost Report"
    echo "================="
    echo ""

    local data
    data=$(get_daily_spend "$target_date")

    local cost sessions
    read -r cost sessions < <(echo "$data" | jq -r '[.cost // 0, .sessions // 0] | @tsv')

    printf "Date:     %s\n" "$target_date"
    printf "Total:    \$%.4f\n" "$cost"
    printf "Sessions: %d\n" "$sessions"
    echo ""

    if [[ "$sessions" -gt 0 ]]; then
        echo "By Spec:"
        echo "--------"
        echo "$data" | jq -r '.specs[] | "  \(.spec | .[0:50])... $\(.cost | tonumber | . * 10000 | round / 10000)"' 2>/dev/null || echo "  (no breakdown available)"
    fi
    echo ""
}

cmd_by_date() {
    local days
    days=$(parse_days "$@")

    echo ""
    echo "Costs by Date (Last $days days)"
    echo "================================"
    echo ""

    local data
    data=$(get_costs_by_date "$days")

    local total
    total=$(get_total_spend "$days")

    printf "Total Spend: \$%.4f\n" "$total"
    echo ""
    printf "%-12s %12s %10s %10s\n" "Date" "Cost" "Sessions" "Specs"
    echo "----------------------------------------------------"

    echo "$data" | jq -r '.[] | "\(.date)    $\(.cost | tonumber | . * 10000 | round / 10000 | tostring | . + "0000" | .[0:7])      \(.sessions)          \(.specs)"' 2>/dev/null || echo "No data found"

    echo ""
}

cmd_by_spec() {
    local days
    days=$(parse_days "$@")

    echo ""
    echo "Costs by Spec (Last $days days)"
    echo "==============================="
    echo ""

    local data
    data=$(get_costs_by_spec "$days")

    local total
    total=$(get_total_spend "$days")

    printf "Total Spend: \$%.4f\n" "$total"
    echo ""

    echo "$data" | jq -r '.[] | "  $\(.cost | tonumber | . * 10000 | round / 10000 | tostring | . + "0000" | .[0:7])  (\(.sessions) sessions)  \(.spec | .[0:40])"' 2>/dev/null || echo "No data found"

    echo ""
}

cmd_by_project() {
    local days
    days=$(parse_days "$@")

    echo ""
    echo "Costs by Project (Last $days days)"
    echo "==================================="
    echo ""

    local data
    data=$(get_costs_by_project "$days")

    local total
    total=$(get_total_spend "$days")

    printf "Total Spend: \$%.4f\n" "$total"
    echo ""

    echo "$data" | jq -r '.[] | "  $\(.cost | tonumber | . * 10000 | round / 10000 | tostring | . + "0000" | .[0:7])  (\(.sessions) sessions, \(.specs) specs)  \(.project | split("/") | .[-2:] | join("/"))"' 2>/dev/null || echo "No data found"

    echo ""
}

cmd_session() {
    if [[ -z "${1:-}" ]]; then
        echo "Error: Session ID required"
        echo ""
        usage
        exit 1
    fi

    local ralph_session="$1"
    local working_dir="${2:-.}"

    echo ""
    echo "Ralph Session Cost Report"
    echo "========================="
    echo ""
    echo "Session:    $ralph_session"
    echo "Directory:  $working_dir"
    echo ""

    # Check if cost summary exists
    local summary_file="$working_dir/.ralph/$ralph_session/cost-summary.json"
    if [[ -f "$summary_file" ]]; then
        local total num_iterations
        total=$(jq -r '.totalCost // 0' "$summary_file")
        num_iterations=$(jq -r '.iterations | length' "$summary_file")

        printf "Total Cost: \$%.4f across %d iterations\n" "$total" "$num_iterations"
        echo ""
        echo "Per-Iteration Breakdown:"
        echo "------------------------"

        jq -r '.iterations[] | "  #\(.iteration | tostring | . + ":" | . + (" " * (4 - (. | length)))) \(.sessionId)  \("$" + (.cost | tonumber | . * 10000 | round / 10000 | tostring))"' "$summary_file"

        echo ""
        echo "Token Usage:"
        echo "------------"

        # Aggregate token stats
        local total_input total_output total_cache_read total_cache_write
        read -r total_input total_output total_cache_read total_cache_write < <(jq -r '[
            ([.iterations[].tokens.input] | add // 0),
            ([.iterations[].tokens.output] | add // 0),
            ([.iterations[].tokens.cacheRead] | add // 0),
            ([.iterations[].tokens.cacheWrite] | add // 0)
        ] | @tsv' "$summary_file")

        LC_NUMERIC=C printf "  Input:       %'d tokens\n" "$total_input"
        LC_NUMERIC=C printf "  Output:      %'d tokens\n" "$total_output"
        LC_NUMERIC=C printf "  Cache Read:  %'d tokens\n" "$total_cache_read"
        LC_NUMERIC=C printf "  Cache Write: %'d tokens\n" "$total_cache_write"
    else
        # Fall back to calculating from sessions file
        local sessions_file="$working_dir/.ralph/$ralph_session/opencode-sessions.txt"
        if [[ ! -f "$sessions_file" ]]; then
            echo "Error: No cost data found for session '$ralph_session'"
            echo ""
            echo "This could mean:"
            echo "  - Session doesn't exist"
            echo "  - Session hasn't completed any iterations yet"
            echo "  - Session was run with claudecode (not opencode)"
            echo ""
            exit 1
        fi

        local total
        total=$(get_ralph_session_cost "$ralph_session" "$working_dir")
        printf "Total Cost: \$%.4f\n" "$total"
        echo ""
        echo "Per-Iteration Breakdown:"
        echo "------------------------"

        while IFS=: read -r iteration opencode_session; do
            [[ -z "$opencode_session" ]] && continue
            local cost
            cost=$(get_opencode_session_cost "$opencode_session")
            printf "  #%-3s: %-35s \$%.4f\n" "$iteration" "$opencode_session" "$cost"
        done < "$sessions_file"
    fi

    echo ""
}

# Main command dispatch
case "${1:-}" in
    session)
        shift
        cmd_session "$@"
        ;;
    daily)
        shift
        cmd_daily "$@"
        ;;
    by-date)
        shift
        cmd_by_date "$@"
        ;;
    by-spec)
        shift
        cmd_by_spec "$@"
        ;;
    by-project)
        shift
        cmd_by_project "$@"
        ;;
    --help|-h)
        usage
        ;;
    *)
        # Pass through to opencode stats (if available)
        if command -v opencode &>/dev/null; then
            opencode stats "$@"
        else
            echo "Error: Unknown subcommand '$1' and opencode is not installed for pass-through" >&2
            echo "Available subcommands: --days, session, --models, --by-project" >&2
            echo "Install opencode: npm install -g @anthropic-ai/opencode" >&2
            exit 1
        fi
        ;;
esac
