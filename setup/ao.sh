#!/usr/bin/env bash
# ao.sh - Install Agent Orchestration aliases for bash/zsh
set -euo pipefail

# Get the parent directory (ralph root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect shell config files
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"

# Detect current shell
CURRENT_SHELL=$(basename "$SHELL")

echo "Agent Orchestration Alias Setup"
echo "================================"
echo ""

# Create the alias block - using new ralph subcommands
ALIAS_BLOCK="# Agent Orchestration aliases
export PATH=\"$SCRIPT_DIR:\$PATH\"

# Main command
alias ao='ralph loop'

# Subcommand shortcuts
alias ao-models='ralph models'
alias ao-cost='ralph cost'
alias ao-stats='ralph stats'
alias ao-agents='ralph agents'
alias ao-cleanup='ralph cleanup'
alias ao-gsd='$SCRIPT_DIR/gsd/gsd-runner'

# Quick shortcuts
alias ao-list='ralph loop --list'
alias ao-help='ralph --help'"

# Function to add aliases to a file
add_aliases() {
    local rc_file="$1"
    local shell_name="$2"

    # Check if aliases already exist
    if grep -q "# Agent Orchestration aliases" "$rc_file" 2>/dev/null; then
        echo "Aliases already exist in $rc_file"
        return 0
    fi

    # Create backup
    if [[ -f "$rc_file" ]]; then
        cp "$rc_file" "${rc_file}.backup.$(date +%Y%m%d-%H%M%S)"
        echo "Created backup: ${rc_file}.backup"
    fi

    # Add aliases
    echo "" >> "$rc_file"
    echo "$ALIAS_BLOCK" >> "$rc_file"
    echo "Added aliases to $rc_file"
}

# Ask user which shell(s) to configure
echo "Detected shell: $CURRENT_SHELL"
echo ""
echo "Which shell configuration would you like to update?"
echo "  1) Bash only (~/.bashrc)"
echo "  2) Zsh only (~/.zshrc)"
echo "  3) Both bash and zsh"
echo "  4) Current shell only ($CURRENT_SHELL)"
echo ""
read -rp "Enter choice [1-4]: " choice

case "$choice" in
    1)
        add_aliases "$BASHRC" "bash"
        CONFIGURED="$BASHRC"
        ;;
    2)
        add_aliases "$ZSHRC" "zsh"
        CONFIGURED="$ZSHRC"
        ;;
    3)
        add_aliases "$BASHRC" "bash"
        add_aliases "$ZSHRC" "zsh"
        CONFIGURED="$BASHRC and $ZSHRC"
        ;;
    4)
        if [[ "$CURRENT_SHELL" == "zsh" ]]; then
            add_aliases "$ZSHRC" "zsh"
            CONFIGURED="$ZSHRC"
        else
            add_aliases "$BASHRC" "bash"
            CONFIGURED="$BASHRC"
        fi
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "================================"
echo "Setup complete!"
echo "================================"
echo ""
echo "Configured: $CONFIGURED"
echo ""
echo "To start using the aliases, either:"
echo "  1. Restart your terminal, or"
echo "  2. Run: source $CONFIGURED"
echo ""
echo "Then try:"
echo "  ralph --help"
echo "  ralph models"
echo "  ralph loop \"Your task here\""
echo ""
