#!/usr/bin/env bash
# common.sh - Entry point for agent-orchestrator libraries
# Source this file: source "$RALPH_ROOT/lib/common.sh"
#
# This file sources all modular libraries for convenience.
# New code should use $RALPH_ROOT to reference the root directory.

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source all core libraries
source "$LIB_DIR/core.sh"
source "$LIB_DIR/model.sh"
source "$LIB_DIR/sandbox.sh"
# All functions are now available from the core libraries:
#
# From core.sh:
#   acquire_lock, release_lock
#   locked_json_update, locked_json_read
#   get_file_size, shuffle_lines, run_with_timeout, format_time_display
#   parse_date_to_epoch, format_epoch_date, get_file_mtime
#
# From model.sh:
#   get_models_for_tier, get_next_available_model
#   is_model_rate_limited, mark_model_rate_limited
#   is_rate_limit_error, load_config_defaults
#
# From sandbox.sh:
#   init_state_dir, check_sandbox_setup
