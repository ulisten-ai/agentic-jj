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

## Releasing

**Bump `version` in `.claude-plugin/plugin.json` for every shipped rule/script change.**
Claude Code's `/plugin update` resolves the installed plugin's version in priority order:
`plugin.json` version → marketplace entry version → git commit SHA → `unknown`. When `version`
is set, `/plugin update` only reports "update available" when that string changes — pushing
commits to `main` without bumping is invisible to existing installs (new sessions still get
the latest via the SessionStart sync, but `/plugin update` users get nothing).

Use semver: patch bump (0.1.0 → 0.1.1) for additive rule entries / wording fixes, minor for
new hooks/skills, major for breaking changes (e.g. renaming a `userConfig` key). Git tags are
**not** consulted by the plugin manager — they're optional repo hygiene, not part of the
version-resolution path.

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
- **Evaluate Claude's handling of bookmark advancement before adding any rule.**
  jj bookmarks don't auto-advance with `jj commit`/`jj new`, so the canonical
  push pattern is `jj bookmark move main -r @ && jj git push` (or `jj bookmark
  advance main`). Before documenting this, test: does current Claude already
  know to move the bookmark before pushing, or does it run `jj git push` against
  a stale bookmark and not notice? If it handles this fine, no rule needed; if
  it forgets, add 3-4 lines under a new "Bookmarks and pushing" section in
  `rules/jj-workflow.md`.
- **Evaluate jj's 3-way conflict format (with guidance) vs git's 2-way format
  for LLM resolution quality.** SPEC §6 plans a hook to nudge users toward
  `ui.conflict-marker-style = "git"` on the assumption that LLM familiarity
  with git markers outweighs the information density of jj's 3-way diff format
  (`%%%%%%%` base + `+++++++` other-side). That assumption is untested. The
  3-way format is strictly information-richer (it shows the base, so the LLM
  doesn't have to infer it), and with ~10 lines of explanatory rules a modern
  model may resolve more accurately in the jj format than in the git format.
  Before committing the README recommendation as universal advice (and before
  building the auto-set hook), run a head-to-head: a handful of real conflicts,
  resolved by Claude under each format with matched guidance, scored on
  correctness. If jj-format-with-guidance wins or ties, flip the README
  recommendation (or qualify it as "for setups without our jj-format rules").
- **Evaluate read-only git allowlist vs flat "never git" rule.** johnstegeman's
  skill (Apache-2.0, jj wiki recommended) distinguishes forbidden git mutations
  (commit/add/stash/reset/checkout/rebase/merge/cherry-pick/push/pull — all
  corrupt jj state) from allowed read-only git (log/show/diff/blame/grep/status
  — safe in colocated repos). Our rule is a flat "never git." Their distinction
  is more practical (read-only git is sometimes convenient — e.g. `git blame`
  output format is what models expect) but adds complexity and risks Claude
  misclassifying a command. Test: does Claude hit cases where it wants read-only
  git and the flat rule blocks something useful, or does the flat rule prevent
  misclassification errors that an allowlist would invite? If the allowlist
  wins, adopt it.
- **Evaluate `jj resolve --tool :ours/:theirs` coverage in rules.** johnstegeman's
  skill (Apache-2.0, jj wiki recommended) flags these as agent-safe non-interactive
  conflict resolution forms — useful when one side is known-correct and manual
  marker editing would be slower. Our rules mention editing conflict markers
  directly but don't surface these flags. Test: when Claude hits a conflict in
  autonomous mode, does it reach for `--tool :ours`/`:theirs` unprompted when
  appropriate, or default to manual marker editing in cases where a clean side
  pick would be faster? If unprompted use is rare and the use case is real,
  add 3-4 lines to rules.
- **Explore using empty described commits as a planning mechanism for Claude.**
  Pre-create a chain of empty `jj describe`-d commits as a plan (each commit's
  description is a step), then fill them in as the implementation progresses.
  Turns the commit chain
  itself into a structured task list, which jj makes cheap (vs git's commit
  semantics). Hypothesized benefits: (1) better planning quality up front;
  (2) clearer plan communication to the user — the commit chain surfaces the
  intended steps directly, without needing a separate plan document;
  (3) better follow-through on long task lists — Claude less likely to drop
  off midway since each completed step has an obvious next. Test on a few
  multi-step tasks; if results are positive, document as a pattern in
  `rules/jj-workflow.md` (or possibly as a slash-command for explicit
  invocation).

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
