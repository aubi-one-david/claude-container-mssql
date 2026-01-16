#!/bin/bash
# Session Save Hook - Called on SessionEnd
# Copies session transcript to project and commits to git

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/workspace}"
SESSION_DIR="$PROJECT_DIR/.claude-sessions"
TRANSCRIPT_DIR="$SESSION_DIR/transcripts"

# Create directories if needed
mkdir -p "$TRANSCRIPT_DIR"

# Find and copy current session transcript
CLAUDE_SESSION_DIR="$HOME/.claude/projects"
if [ -d "$CLAUDE_SESSION_DIR" ]; then
    # Find most recent session file (modified in last 60 minutes)
    LATEST=$(find "$CLAUDE_SESSION_DIR" -name "*.jsonl" -mmin -60 -type f 2>/dev/null | head -1)

    if [ -n "$LATEST" ] && [ -f "$LATEST" ]; then
        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        DEST="$TRANSCRIPT_DIR/${TIMESTAMP}.jsonl"

        cp "$LATEST" "$DEST"
        echo "Session saved to: $DEST"

        # Git commit if in a repo
        if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
            cd "$PROJECT_DIR"

            # Add session files
            git add .claude-sessions/ 2>/dev/null || true

            # Check if there are changes to commit
            if ! git diff --cached --quiet 2>/dev/null; then
                git commit -m "chore(session): auto-save $(date +%Y-%m-%d_%H:%M)" \
                    --author="Claude Container <claude@container.local>" \
                    --no-verify 2>/dev/null || true
                echo "Session committed to git"
            fi
        fi
    else
        echo "No recent session transcript found"
    fi
else
    echo "Claude session directory not found"
fi

exit 0
