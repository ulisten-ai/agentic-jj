# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code **plugin** that teaches Claude how to use jujutsu (jj) effectively.
Published as `agentic-jj` at github.com/ulisten-ai/agentic-jj (MIT).

## Current State

**v0 (shipped):** rules only. The plugin provides:
- `.claude-plugin/{plugin,marketplace}.json` — installable via `/plugin marketplace add ulisten-ai/agentic-jj`
- `rules/jj-workflow.md` (~265 lines) — always-on jj guidance
- `scripts/sync-rules.sh` + `hooks/hooks.json` — SessionStart hook that syncs rules to
  `<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md` and bootstraps `*.local.md`
  into the project's `.gitignore`
- `README.md`, `LICENSE` (MIT)

**Planned (not yet built):**
- **Skills** (on-demand) for complex operations: `jj-split`, `jj-rewrite-history`, `jj-recovery`
- **Safety hooks**: block-git (in jj repos), check-interactive (intercept editor-opening jj commands),
  auto-snapshot (preserve work on session stop), inject-state (show `jj status` at session start)
- **Configuration via `userConfig`** for toggling safety hooks

## Target Structure (full spec — see SPEC.md)

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

## Pending Work

Each independently useful — pick any:

- **Skill: jj-split** — non-interactive splitting recipes (by file, restore-pivot for hunks)
- **Skill: jj-rewrite-history** — partial squash, rebase, insert mid-chain
- **Skill: jj-recovery** — op log, undo, restore, obslog recipes
- **Hook: block-git** — `PreToolUse` matcher on `Bash(git *)` that blocks git commands when `jj root` succeeds
- **Hook: check-interactive** — `PreToolUse` matcher on `Bash(jj *)` that blocks editor-opening forms (`jj describe` without `-m`, `jj split` without `-m + --`, etc.)
- **Hook: auto-snapshot** — `Stop` hook that describes undescribed working copy as WIP
- **Hook: inject-jj-state** — `SessionStart` extension to also output `jj status` + `jj log -r @`
- **`userConfig`** — toggles for each hook (`auto_snapshot`, `block_git`, etc.)
- **CHANGELOG**

## Hook Implementation Conventions (for the planned hooks above)

1. Check if we're in a jj repo (`jj root`) — exit silently if not
2. Read config env var (`CLAUDE_PLUGIN_OPTION_<NAME>`) — exit silently if disabled
3. `PreToolUse` scripts receive event JSON on stdin and output `{"decision": "block"|"approve", "reason": "..."}` JSON
4. Use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths

## Testing

No automated framework. Verify manually after changes:
- Install the plugin from local path (`/plugin marketplace add /Users/ahaan/dev/podwiz/jj-claude`) into a test repo; start a fresh Claude Code session; confirm a rules-specific question (e.g. "what's the restore-pivot trick?") is answered without grepping
- Confirm the sync writes `<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md` and bootstraps `*.local.md` in `.gitignore`
- Confirm it no-ops cleanly when `$CLAUDE_PROJECT_DIR` isn't set
- Target jj 0.25+ (bookmark vs branch rename happened ~0.22; tested with 0.40)
