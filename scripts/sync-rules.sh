#!/bin/bash
# SessionStart hook: sync the agentic-jj workflow rules into the current
# project at .claude/rules/ulisten/agentic-jj/jj-workflow.local.md
#
# Project-scoped (respects the plugin's install scope; no global writes
# to ~/.claude/rules/). Claude Code auto-loads any markdown file under
# <project>/.claude/rules/ recursively, so the synced file lands in
# Claude's primary context window for every session in this project.
#
# The destination uses the .local.md suffix so it's covered by the
# common *.local.md gitignore convention. If the project's .gitignore
# doesn't already match it, this hook appends *.local.md once.
# Idempotent on every run.

[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

SOURCE_FILE="${CLAUDE_PLUGIN_ROOT}/rules/jj-workflow.md"
[ -f "$SOURCE_FILE" ] || exit 0

DEST_DIR="$CLAUDE_PROJECT_DIR/.claude/rules/ulisten/agentic-jj"
DEST_FILE="$DEST_DIR/jj-workflow.local.md"

mkdir -p "$DEST_DIR"
if ! diff -q "$SOURCE_FILE" "$DEST_FILE" > /dev/null 2>&1; then
  cp "$SOURCE_FILE" "$DEST_FILE"
fi

GITIGNORE="$CLAUDE_PROJECT_DIR/.gitignore"
PATTERN='*.local.md'
if [ -f "$GITIGNORE" ]; then
  grep -qxF "$PATTERN" "$GITIGNORE" || echo "$PATTERN" >> "$GITIGNORE"
else
  echo "$PATTERN" > "$GITIGNORE"
fi
