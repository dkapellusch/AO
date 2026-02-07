#!/usr/bin/env bash
# stats.sh - Analyze ralph loop session data and display statistics
# Invoked via: ralph stats [OPTIONS]

RALPH_SESSION_STATE="$RALPH_STATE_DIR/ralph"

# Defaults
OUTPUT_JSON=false
VERBOSE=false

usage() {
    cat <<EOF
Usage: ralph stats [OPTIONS]

Analyze ralph loop session data and display comprehensive statistics.

Options:
  --json        Output as JSON instead of formatted text
  --verbose     Show list of all sessions with details
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --json) OUTPUT_JSON=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ ! -d "$RALPH_SESSION_STATE" ]] || [[ -z "$(ls -A "$RALPH_SESSION_STATE"/*.json 2>/dev/null)" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "{
  \"sessions\": {
    \"total\": 0,
    \"completed\": 0,
    \"failed\": 0,
    \"running\": 0,
    \"successRate\": \"0.0%\"
  },
  \"iterations\": {
    \"total\": 0,
    \"averagePerCompleted\": \"0.0\",
    \"minCompleted\": 0,
    \"maxCompleted\": 0
  },
  \"activity\": {
    \"oldest\": null,
    \"newest\": null,
    \"last24h\": 0,
    \"last7d\": 0
  }
}"
    else
        echo "No sessions found in $RALPH_SESSION_STATE"
    fi
    exit 0
fi

# Initialize variables
total_sessions=0
completed_sessions=0
failed_sessions=0
running_sessions=0

total_iterations=0
completed_iterations_sum=0
min_completed_iterations=999999
max_completed_iterations=0

oldest_date_sec=""
newest_date_sec=""
sessions_24h=0
sessions_7d=0

now_sec=$(date +%s)
# 24 hours in seconds: 86400
# 7 days in seconds: 604800

for session_file in "$RALPH_SESSION_STATE"/*.json; do
    # Skip if not a file
    [[ -f "$session_file" ]] || continue

    # Read essential fields
    if ! json_content=$(cat "$session_file" 2>/dev/null); then
        echo "Warning: Could not read $session_file" >&2
        continue
    fi

    # Validate valid JSON
    if ! echo "$json_content" | jq empty 2>/dev/null; then
         echo "Warning: Invalid JSON in $session_file" >&2
         continue
    fi

    # Extract needed fields in one go
    read -r id status iterations started_at <<< "$(echo "$json_content" | jq -r '[.id // "", .status // "unknown", .iteration // 0, .startedAt // ""] | @tsv')"

    # Skip if no ID
    if [[ -z "$id" ]]; then continue; fi

    total_sessions=$((total_sessions + 1))

    # Status Counts
    case "$status" in
        "completed")
            completed_sessions=$((completed_sessions + 1))
            completed_iterations_sum=$((completed_iterations_sum + iterations))
            if (( iterations < min_completed_iterations )); then min_completed_iterations=$iterations; fi
            if (( iterations > max_completed_iterations )); then max_completed_iterations=$iterations; fi
            ;;
        "running")
            running_sessions=$((running_sessions + 1))
            ;;
        "failed"|"error"|"max_iterations"|"rate_limit_exhausted")
            failed_sessions=$((failed_sessions + 1))
            ;;
        *)
            failed_sessions=$((failed_sessions + 1))
            ;;
    esac

    total_iterations=$((total_iterations + iterations))

    # Timing
    if [[ -n "$started_at" ]]; then
        # Convert to seconds
        start_sec=$(parse_date_to_epoch "$started_at")
        if [[ -n "$start_sec" ]]; then
            # Min/Max date
            if [[ -z "$oldest_date_sec" ]]; then oldest_date_sec=$start_sec; fi
            if [[ -z "$newest_date_sec" ]]; then newest_date_sec=$start_sec; fi

            if (( start_sec < oldest_date_sec )); then oldest_date_sec=$start_sec; fi
            if (( start_sec > newest_date_sec )); then newest_date_sec=$start_sec; fi

            diff=$((now_sec - start_sec))
            if (( diff <= 86400 )); then sessions_24h=$((sessions_24h + 1)); fi
            if (( diff <= 604800 )); then sessions_7d=$((sessions_7d + 1)); fi
        fi
    fi
done

# Calculate averages
avg_completed_iterations=0
if (( completed_sessions > 0 )); then
    avg_completed_iterations=$(awk -v sum="$completed_iterations_sum" -v count="$completed_sessions" 'BEGIN {printf "%.1f", sum / count}')
else
    min_completed_iterations=0
fi

success_rate=0
if (( total_sessions > 0 )); then
    success_rate=$(awk -v completed="$completed_sessions" -v total="$total_sessions" 'BEGIN {printf "%.1f", (completed / total) * 100}')
fi

# Format dates
oldest_date_str="N/A"
newest_date_str="N/A"
if [[ -n "$oldest_date_sec" ]]; then oldest_date_str=$(format_epoch_date "$oldest_date_sec" "+%Y-%m-%d"); fi
if [[ -n "$newest_date_sec" ]]; then newest_date_str=$(format_epoch_date "$newest_date_sec" "+%Y-%m-%d"); fi

if [[ "$OUTPUT_JSON" == "true" ]]; then
    jq -n \
        --argjson total "$total_sessions" \
        --argjson completed "$completed_sessions" \
        --argjson failed "$failed_sessions" \
        --argjson running "$running_sessions" \
        --arg successRate "$success_rate" \
        --argjson totalIterations "$total_iterations" \
        --arg avgIterations "$avg_completed_iterations" \
        --argjson minIterations "$min_completed_iterations" \
        --argjson maxIterations "$max_completed_iterations" \
        --arg oldest "$oldest_date_str" \
        --arg newest "$newest_date_str" \
        --argjson last24h "$sessions_24h" \
        --argjson last7d "$sessions_7d" \
        '{
            sessions: {
                total: $total,
                completed: $completed,
                failed: $failed,
                running: $running,
                successRate: ($successRate + "%")
            },
            iterations: {
                total: $totalIterations,
                averagePerCompleted: $avgIterations,
                minCompleted: $minIterations,
                maxCompleted: $maxIterations
            },
            activity: {
                oldest: $oldest,
                newest: $newest,
                last24h: $last24h,
                last7d: $last7d
            }
        }'
else
    # Text output
    echo "Ralph Loop Statistics"
    echo "====================="
    echo ""
    echo "Sessions:"
    echo "  Total:      $total_sessions"
    echo "  Completed:  $completed_sessions ($success_rate%)"
    echo "  Failed:     $failed_sessions"
    echo "  Running:    $running_sessions"
    echo ""
    echo "Iterations:"
    echo "  Total:      $total_iterations"
    echo "  Average:    $avg_completed_iterations per completed session"
    if (( completed_sessions > 0 )); then
        echo "  Range:      $min_completed_iterations - $max_completed_iterations"
    else
        echo "  Range:      N/A"
    fi
    echo ""
    echo "Activity:"
    echo "  First:      $oldest_date_str"
    echo "  Latest:     $newest_date_str"
    echo "  Last 24h:   $sessions_24h sessions"
    echo "  Last 7d:    $sessions_7d sessions"

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "Detailed Session List:"
        printf "%-10s %-20s %-5s %-20s\n" "ID" "Status" "Iter" "Started"
        echo "---------- -------------------- ----- --------------------"
        for session_file in "$RALPH_SESSION_STATE"/*.json; do
            [[ -f "$session_file" ]] || continue
            jq -r '[.id, .status, .iteration, .startedAt] | @tsv' "$session_file" | \
            while read -r id stat iter start; do
                printf "%-10s %-20s %-5s %s\n" "$id" "$stat" "$iter" "$start"
            done
        done
    fi
fi
