#!/usr/bin/env bash
# cleanup.sh - Manage old ralph session files
# Invoked via: ralph cleanup [OPTIONS]

# Ensure core functions are available (when invoked standalone or by tests)
if ! declare -f get_file_size &>/dev/null; then
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
fi

RALPH_SESSION_STATE="$RALPH_STATE_DIR/ralph"

# Defaults
DAYS=7
STATUS_FILTER=""
KEEP_LAST=0
DRY_RUN=true
FORCE=false

usage() {
    cat <<EOF
Usage: ralph cleanup [OPTIONS]

Manage old ralph session files by deleting those that meet specific criteria.

Options:
  --days N          Delete sessions older than N days (default: 7)
  --status STATUS   Only clean sessions with specific status (completed, failed, etc.)
  --keep-last N     Always keep the N most recent sessions regardless of age
  --dry-run         Show what would be deleted without deleting (default)
  --force           Actually delete the files
  -h, --help        Show this help

Safety:
  Sessions with status "running" are NEVER deleted.
  If neither --dry-run nor --force is specified, defaults to dry-run behavior.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }
            DAYS="$2"
            if [[ ! "$DAYS" =~ ^[0-9]+$ ]]; then
                echo "Error: --days must be a positive integer, got '$DAYS'" >&2
                exit 1
            fi
            shift 2
            ;;
        --status) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; STATUS_FILTER="$2"; shift 2 ;;
        --keep-last)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }
            KEEP_LAST="$2"
            if [[ ! "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
                echo "Error: --keep-last must be a positive integer, got '$KEEP_LAST'" >&2
                exit 1
            fi
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; DRY_RUN=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ ! -d "$RALPH_SESSION_STATE" ]]; then
    echo "State directory not found: $RALPH_SESSION_STATE"
    exit 0
fi

# Collect all sessions
files=("$RALPH_SESSION_STATE"/*.json)
if [[ ! -e "${files[0]}" ]]; then
    echo "No sessions found in $RALPH_SESSION_STATE"
    exit 0
fi

now_sec=$(date +%s)
threshold_sec=$((now_sec - (DAYS * 86400)))

# We'll store session info in a way we can sort/filter
# Format: timestamp|status|file_path|id
session_list=()

for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue

    # Read status and updatedAt (fallback to startedAt)
    # Using jq to get updatedAt, startedAt, and status
    data=$(jq -r '[.updatedAt // .startedAt // "", .status // "unknown", .id // "unknown"] | @tsv' "$f" 2>/dev/null) || continue
    read -r updated_at status id <<< "$data"

    if [[ -z "$updated_at" ]]; then
        # Use file modification time as last resort
        ts=$(get_file_mtime "$f")
    else
        ts=$(parse_date_to_epoch "$updated_at")
        if [[ -z "$ts" ]]; then
            ts=$(get_file_mtime "$f")
        fi
    fi

    session_list+=("$ts|$status|$f|$id")
done

# Sort sessions by timestamp descending (newest first)
sorted_sessions=()
while IFS= read -r line; do
    sorted_sessions+=("$line")
done < <(printf '%s\n' "${session_list[@]}" | sort -rn)

total_found=${#sorted_sessions[@]}
to_delete=()

# First pass: Collect all statuses for counting (bash 3.2 compatible)
all_statuses=""
for entry in "${sorted_sessions[@]}"; do
    IFS='|' read -r ts status f id <<< "$entry"
    all_statuses+="$status"$'\n'
done

# Second pass: Identify candidates for deletion
kept_count=0
for entry in "${sorted_sessions[@]}"; do
    IFS='|' read -r ts status f id <<< "$entry"

    # Rule 1: NEVER delete running
    if [[ "$status" == "running" ]]; then
        continue
    fi

    # Rule 2: Keep last N
    if [[ $kept_count -lt $KEEP_LAST ]]; then
        kept_count=$((kept_count + 1))
        continue
    fi

    # Rule 3: Filter by status if specified
    if [[ -n "$STATUS_FILTER" ]] && [[ "$status" != "$STATUS_FILTER" ]]; then
        continue
    fi

    # Rule 4: Age threshold
    if [[ $ts -lt $threshold_sec ]]; then
        to_delete+=("$entry")
    fi
done

# Output results
echo "Sessions found: $total_found"
# Count each unique status (bash 3.2 compatible)
status_line=""
unique_statuses=$(echo -n "$all_statuses" | sort -u)
while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    count=$(echo -n "$all_statuses" | grep -c "^${s}$" || echo 0)
    status_line+="${s}: ${count}, "
done <<< "$unique_statuses"
echo "Status breakdown: ${status_line%, }"
echo ""

if [[ ${#to_delete[@]} -eq 0 ]]; then
    echo "No sessions matched the cleanup criteria."
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "WOULD DELETE (${#to_delete[@]} sessions):"
else
    echo "DELETING (${#to_delete[@]} sessions):"
fi

total_reclaimed=0
for entry in "${to_delete[@]}"; do
    IFS='|' read -r ts status f id <<< "$entry"

    size=$(get_file_size "$f")
    total_reclaimed=$((total_reclaimed + size))

    age_days=$(( (now_sec - ts) / 86400 ))
    printf "  - %-10s (status: %-12s, age: %3d days, size: %8d bytes)\n" "$id" "$status" "$age_days" "$size"

    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f "$f"
    fi
done

echo ""
reclaimed_kb=$(awk -v total="$total_reclaimed" 'BEGIN {printf "%.2f", total / 1024}')
if [[ "$DRY_RUN" == "true" ]]; then
    echo "Total disk space that would be reclaimed: ${reclaimed_kb} KB"
else
    echo "Total disk space reclaimed: ${reclaimed_kb} KB"
fi
