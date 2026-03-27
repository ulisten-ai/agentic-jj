# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code **plugin** that teaches Claude how to use jujutsu (jj) effectively. It provides:
- **Rules** (always-loaded context) for core jj workflow and non-interactive command patterns
- **Skills** (on-demand) for complex operations: splitting, history rewriting, recovery
- **Hooks** for safety: blocking git commands in jj repos, blocking interactive jj commands, auto-snapshotting on session stop

## Target Structure

See `SPEC.md` for the full specification. Key directories:

- `.claude-plugin/plugin.json` — plugin manifest with metadata and `userConfig`
- `rules/jj-workflow.md` — always-on guidance, synced to `<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md` by SessionStart hook
- `skills/{jj-split,jj-rewrite-history,jj-recovery}/SKILL.md` — on-demand complex recipes
- `hooks/hooks.json` — lifecycle hook definitions (SessionStart, Stop, PreToolUse)
- `scripts/*.sh` — shell scripts referenced by hooks

## Key Design Decisions

- **CLI over MCP**: jj is a stateless CLI; MCP adds no value and wastes ~13k context tokens on tool schemas.
- **Rules for always-on, Skills for on-demand**: Rules file must stay concise (always in context window). Complex multi-step recipes go in skills.
- **Rules sync pattern**: SessionStart hook copies `rules/jj-workflow.md` → `<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md`. Claude Code auto-loads every `.md` under `<project>/.claude/rules/` recursively into primary context — so rules are always-on but scoped to the project (no global `~/.claude/rules/` pollution). The `.local.md` suffix piggybacks on the common `*.local.md` gitignore convention; the script bootstraps the pattern if absent.
- **Configuration via userConfig**: Each hook reads `CLAUDE_PLUGIN_OPTION_*` env vars and no-ops if disabled. Config keys: `auto_snapshot`, `block_git`, `block_interactive`, `session_state_inject`, `diff_flag`.

## Hook Scripts

All scripts must:
1. Check if we're in a jj repo (`jj root`) — exit silently if not
2. Read their config env var — exit silently if disabled
3. PreToolUse scripts receive event JSON on stdin and must output `{"decision": "block"|"approve", "reason": "..."}` as JSON
4. Use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths, `${CLAUDE_PLUGIN_DATA}` for persistent data

## Testing

No automated test framework. Testing is manual per `SPEC.md § Testing Plan`:
- Verify rules load and Claude follows describe-first workflow
- Verify skill auto-invocation for split/rebase/recovery tasks
- Verify each hook fires correctly (block-git, check-interactive, auto-snapshot, inject-state)
- Verify config toggles disable corresponding hooks
- Verify graceful no-op in non-jj repos
- Target jj 0.25+ (bookmark vs branch rename happened ~0.22)
