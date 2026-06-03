# agentic-jj: Plugin Specification

A Claude Code plugin that teaches Claude how to use jujutsu (jj) effectively, with
automation hooks for safety and workflow enforcement.

**Status:** v0 shipped — covers the **rules + sync hook** portion only. Skills,
safety hooks, and `userConfig` toggles described later in this doc are forward-looking
design, not yet built (tracked as "Pending Work" in `CLAUDE.md`).

## Goals

1. **Cover the hard stuff.** Existing jj skills cover basics well but fall short on complex
   operations: splits, partial squashes, rebasing, revsets, op log recovery. This plugin
   prioritizes depth over breadth.

2. **Prevent common agent mistakes.** Hooks that intercept git commands in jj repos, block
   interactive commands, and auto-snapshot work to prevent data loss.

3. **Opinionated workflow.** This plugin prescribes a specific workflow (snapshot-often
   with clear descriptions, squash-when-verified) rather than trying to accommodate all
   possible jj workflows. Configuration is available for specific toggles, not wholesale
   workflow changes.

## Workflow Philosophy

The plugin enforces this workflow:

1. **Before starting work:** Check `jj log -r @`. If the current change already has a
   description, `jj new` first to avoid mixing unrelated edits.
2. **While working:** The working copy `@` is always the current change. No staging, no
   explicit commits needed — just edit files.
3. **Describe frequently:** `jj describe -m "..."` to document what the current change does.
4. **Snapshot often:** `jj describe` + `jj new` to checkpoint. Multiple snapshots in a chain
   are expected; squash later to consolidate.
5. **Squash when verified:** Don't squash until the change is confirmed working. Use
   `jj squash --into <target> -m "message"` to consolidate.
6. **Abandon freely:** `jj abandon` any snapshot that didn't work out. The op log preserves
   everything if you need to recover.
7. **Never use git commands** in a jj repo.

## Plugin Structure

Files marked `(v0)` are shipped; `(planned)` are still to be built.

```
agentic-jj/
├── .claude-plugin/
│   ├── plugin.json              # (v0) plugin manifest
│   └── marketplace.json         # (v0) marketplace manifest (single-plugin)
├── rules/
│   └── jj-workflow.md           # (v0) synced to <project>/.claude/rules/ on SessionStart
├── skills/
│   ├── jj-split/
│   │   └── SKILL.md             # (planned) non-interactive splitting recipes
│   ├── jj-rewrite-history/
│   │   └── SKILL.md             # (planned) partial squash, rebase, insert mid-chain
│   └── jj-recovery/
│       └── SKILL.md             # (planned) op log, undo, restore, obslog
├── hooks/
│   └── hooks.json               # (v0) currently wires SessionStart only
├── scripts/
│   ├── sync-rules.sh            # (v0) SessionStart: sync rules + bootstrap .gitignore
│   ├── auto-snapshot.sh         # (planned) Stop: describe + new if @ has undescribed changes
│   ├── block-git.sh             # (planned) PreToolUse: block git commands in jj repos
│   ├── check-interactive.sh     # (planned) PreToolUse: block editor-opening jj commands
│   └── inject-jj-state.sh       # (planned) SessionStart: output jj status/log for context
├── README.md                    # (v0)
├── LICENSE                      # (v0) MIT
└── SPEC.md                      # (v0) this file
```

## Rules vs Skills

This plugin uses **both** mechanisms for different purposes:

**Rules** (`rules/jj-workflow.md`) — always-on guidance:
- Synced to `<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md` by a
  SessionStart hook
- Auto-loaded into Claude's primary context — Claude sees them every conversation
- Contains: core mental model, non-interactive command rules, viewing state, the
  describe-and-snapshot workflow, revsets, bookmarks, conflict handling
- Should be concise — this consumes context window in every conversation

**Skills** (`skills/*/SKILL.md`) — on-demand complex recipes:
- Invoked by Claude when it matches the description, or by user via `/jj-split` etc.
- Contains: detailed step-by-step recipes for complex operations that only need to be
  in context when the user is actually doing that operation
- Can be longer and more detailed since they only load when needed

**How rules sync works:**
1. Plugin ships `rules/jj-workflow.md`
2. `scripts/sync-rules.sh` runs on `SessionStart`, syncs to
   `$CLAUDE_PROJECT_DIR/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md`
   (skips the copy when content is unchanged)
3. Claude Code auto-loads every `.md` file under `<project>/.claude/rules/` recursively
   into the session's primary context — so rules are always-on but scoped to the
   project, with no global `~/.claude/rules/` pollution
4. The `.local.md` suffix means the file is covered by the common `*.local.md` gitignore
   convention; the script bootstraps that pattern in `.gitignore` if it's missing

## Rules Content (rules/jj-workflow.md)

See `rules/jj-workflow.md` for the actual rules.

**Design principles:**

- **Concise** — every line costs context window in every conversation.
- **Focus on what Claude gets wrong**, not jj basics. Assume Claude has core jj
  knowledge from training data; the rules cover the deltas and gotchas.
- **Always-on** (no opt-out). The rules file IS the plugin's core value, so the
  SessionStart sync is not gated by `userConfig`.

**Topics, intended format, and current state:**

| Topic | Intended format | Status in `rules/jj-workflow.md` |
|---|---|---|
| Core mental model | 5-bullet summary (see below) | Scattered in prose; no consolidated summary |
| Non-interactive commands | Table of command → problem → alternative (see below) | Prose across multiple sections; no consolidated table |
| Viewing state | List of `jj status` / `diff --git` / `show --git` / `log` / `log -r <revset>` with `--git`-for-diffs reminder | ✓ covered in **Core Rules** |
| Workflow | Decision tree (see below) | Prose in **Commit Management**; no decision-tree formatting |
| Revset quick reference | Operator reference table (see below) | **Gap** — not in rules |
| Bookmarks and pushing | Command list (see below) | **Gap** — not in rules |
| Conflict handling | Marker syntax + recovery commands (see below) | **Gap** — not in rules |

### Format details

#### Core mental model

Brief but precise. Not a jj tutorial — assume Claude has basic jj knowledge from training
data. Focus on what it gets wrong:

- Working copy IS a change (no staging area)
- Change IDs (stable across rebases) vs commit IDs (change on rewrite)
- `@` = working copy, `@-` = parent, `@--` = grandparent
- All changes are mutable until pushed
- The working copy auto-snapshots on every jj command

#### Non-interactive command table

**Critical section.** Claude's #1 failure mode is running commands that open an editor
or interactive UI. The table should cover at minimum:

| Command | Problem | Non-interactive alternative |
|---------|---------|---------------------------|
| `jj describe` (no `-m`) | Opens editor | `jj describe -m "message"` (or `--stdin` for multi-line) |
| `jj commit` (no `-m`) | Opens editor | `jj commit -m "message"` (or just describe + new) |
| `jj split` | Interactive file/hunk picker | `jj split -m "msg" -- <files>` (file-level); see `jj-split` skill for hunk-level |
| `jj resolve` | Opens merge tool | Edit conflict markers directly, then save |
| `jj squash` (no `-m`, target has description) | Opens editor to combine messages | `jj squash -m "message"` |

#### Workflow decision tree

```
Starting new work:
  jj log -r @  →  has description?  →  yes: jj new -m "task description"
                                    →  no:  jj describe -m "task description"

Checkpointing (snapshot):
  jj describe -m "what this change does"
  jj new

Finishing a task:
  jj describe -m "final description"
  jj new   # clean slate for next task

Discarding a failed attempt:
  jj abandon @   # drops current change, moves @ to parent

Squashing (after verified):
  jj squash --into <target> -m "message"   # squash @ into any target change
  jj squash -m "message"                    # squash @ into parent
```

#### Revset quick reference

```
@                            current change
@-                           parent of current
@--                          grandparent
trunk()                      the main branch tip
trunk()..@                   all changes between trunk and current
<x>+                         children of x
<x>-                         parent of x
ancestors(<x>)               all ancestors
heads(<set>)                 tip changes in a set
empty()                      changes with no diff
description(substring:"X")   changes whose description contains "X"
mine()                       changes by current user
```

#### Bookmarks and pushing

```bash
jj bookmark create <name> -r @      # create (doesn't auto-advance like git branches)
jj bookmark set <name> -r @         # move to current change
jj git push --bookmark <name>       # push specific bookmark
jj git push                         # push all tracked bookmarks
jj git fetch                        # fetch from remote
```

#### Conflict handling

```bash
# After a rebase that creates conflicts:
jj log     # conflicted changes show "conflict" marker

# Edit the conflicted files directly (jj conflict markers):
# <<<<<<<
# %%%%%%%  (diff from one side)
# +++++++  (content from other side)
# >>>>>>>

# After resolving, just save the file — jj auto-snapshots

# If resolution went wrong:
jj restore --from @- path/to/file
```

## Skills Content

Skills are loaded on-demand when Claude needs them for complex operations. Each skill
should have a clear `description` in its frontmatter so Claude auto-invokes it at the
right time.

### Skill: jj-split (skills/jj-split/SKILL.md)

**Description:** "Non-interactive alternatives to `jj split` for separating changes into
multiple commits. Use when the user wants to split a change, move files between changes,
or extract part of a change into a separate commit."

Content:

#### Split by file (move specific files to a new change)

```bash
# Current state: @ has changes to files A, B, C
# Goal: put A, B in one change and C in another

jj describe -m "changes to A and B"     # describe what stays
jj new @                                  # new child of current
jj restore --from @- -- path/to/C        # pull C into new change
jj describe -m "changes to C"

# Now @- has A+B+C, @ has C
# Remove C from the parent:
jj new @-                                # move to parent
jj restore --from @-- -- path/to/C       # restore C from grandparent (removes it)
```

#### Alternative approach — extract files out first

```bash
# Start a new change, move the files you want to separate
jj new @-                                # new sibling of current change
jj restore --from @+ -- path/to/C       # copy C from the original
jj describe -m "changes to C"
# Original change still has A+B+C; remove C from it:
jj edit <original-change-id>
jj restore --from @- -- path/to/C       # restore C to pre-change state
```

> For hunk-level splits within a shared file, use the **restore-pivot trick**
> (`jj edit C; jj restore --from <pre-state-hash>; jj new; jj restore --from <post-state-hash>`)
> — see `rules/jj-workflow.md` for the recipe. Pre-state and post-state hashes come from
> `jj op log`.

### Skill: jj-rewrite-history (skills/jj-rewrite-history/SKILL.md)

**Description:** "Rewrite jujutsu commit history: partial squash, rebase, and inserting
changes mid-chain. Use when the user wants to reorganize commits, move changes between
revisions, or restructure the commit graph."

Content:

#### Partial Squash (squash specific files into a target)

```bash
# Squash only specific files from @ into <target>
jj squash --into <target> -- path/to/file

# Squash everything from @ into a non-parent target
jj squash --into <target> -m "message"
```

The `--` separator allows specifying paths. Without it, the entire change is squashed.

#### Rebasing

```bash
# Move a single change to a new parent
jj rebase -r <change> -d <new-parent>

# Move a change and all its descendants
jj rebase -s <change> -d <new-parent>

# Move everything from a change to tip onto a new base
jj rebase -b <change> -d <new-parent>

# Rebase onto multiple parents (merge)
jj rebase -r <change> -d <parent1> -d <parent2>
```

#### Inserting Changes Mid-Chain

```bash
# Insert a new empty change before <target> (target becomes its child)
jj new --insert-before <target>

# Insert a new empty change after <target> (target's children become its children)
jj new --insert-after <target>
```

### Skill: jj-recovery (skills/jj-recovery/SKILL.md)

**Description:** "Recover from mistakes using jujutsu's operation log. Use when the user
wants to undo operations, restore previous state, view operation history, or recover
lost changes."

Content:

#### Operation Log

Every jj command is recorded in the operation log (append-only). Nothing is ever truly lost.

```bash
# View the operation log
jj op log

# Inspect what an op did (mandatory before reverting)
jj op show <operation-id> --git --patch

# Inverse a specific op (preferred — surgical, preserves later work)
jj op revert <operation-id>
```

**NEVER use `jj op restore`** — it appends a new op that resets state to the target,
abandoning every operation made since (including snapshots from concurrent workspaces).
Prefer `jj op revert <op>` over `jj undo` too: revert takes an explicit op id, forcing
you to look at the log first; `jj undo` blindly reverts the latest op, which is risky
when recent ops are intermingled snapshots from tool calls and editor saves.

#### Obslog (Change History)

Track how a specific change has been rewritten over time:

```bash
# View all versions of a change (through rebases, squashes, etc.)
jj obslog -r <change>

# With diffs to see what changed in each rewrite
jj obslog -r <change> -p --git
```

#### Recovery Recipes

**Accidentally abandoned a change:**
```bash
jj op log                            # find the abandon op
jj op show <abandon-op> --git        # confirm it's the right one
jj op revert <abandon-op>            # inverse just that op
```

**Accidentally squashed the wrong thing:**
```bash
jj op log                            # find the squash op
jj op revert <squash-op>             # inverse it
```

**Want to see what @ looked like before a rebase:**
```bash
jj obslog -r <change>               # shows all historical versions
```

## Hooks

### hooks.json Structure

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/sync-rules.sh" },
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-jj-state.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/auto-snapshot.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash(git *)",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git.sh" }
        ]
      },
      {
        "matcher": "Bash(jj *)",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/check-interactive.sh" }
        ]
      }
    ]
  }
}
```

### 1. SessionStart: Sync Rules File (sync-rules.sh) ✓ implemented

See `scripts/sync-rules.sh` for the actual logic (~25 lines, self-documenting).
Syncs `${CLAUDE_PLUGIN_ROOT}/rules/jj-workflow.md` →
`$CLAUDE_PROJECT_DIR/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md` and
bootstraps `*.local.md` into the project's `.gitignore` if missing. Idempotent.

Not configurable — always runs. The rules file IS the plugin's core value.

### 2. SessionStart: Inject jj State (inject-jj-state.sh)

**Purpose:** Add current jj state to the conversation context at session start.

Script logic:
1. Check if we're in a jj repo (`jj root` succeeds)
2. If yes, output current state:
   - Output of `jj status`
   - Output of `jj log -r @`
   - Whether `@` has a description (to decide if `jj new` is needed before starting)
3. If not a jj repo, exit silently

**Configuration:** `session_state_inject` (default: `true`)

### 3. Stop: Auto-Snapshot (auto-snapshot.sh)

**Purpose:** If the working copy has undescribed changes, describe them as WIP to prevent
work from being lost if the session ends unexpectedly.

Script logic:
1. Check if we're in a jj repo (`jj root` succeeds)
2. Check if `@` has modifications (`jj status` shows changes)
3. Check if `@` has no description (`jj log -r @ -T description --no-graph` is empty)
4. If all true: `jj describe -m "WIP: auto-snapshot from Claude Code session"`

Note: This only adds a description — it does NOT run `jj new`. The user or next session
can decide whether to continue editing `@` or start fresh.

**Configuration:** `auto_snapshot` (default: `true`)

### 4. PreToolUse: Block Git Commands (block-git.sh)

**Matcher:** `Bash(git *)`
**Purpose:** Prevent Claude from running git commands in a jj repo.

Script logic:
1. Check if we're in a jj repo (`jj root` succeeds)
2. If yes: output `{"decision": "block", "reason": "...use jj instead..."}`, exit 0
3. If not a jj repo: output `{"decision": "approve"}`, exit 0

**Configuration:** `block_git` (default: `true`)

### 5. PreToolUse: Block Interactive Commands (check-interactive.sh)

**Matcher:** `Bash(jj *)`
**Purpose:** Intercept jj commands that would open an editor or interactive UI.

Script logic:
1. Parse the command from stdin JSON
2. Check if it matches known interactive patterns:
   - `jj split` (any form)
   - `jj describe` without `-m`
   - `jj commit` without `-m`
   - `jj resolve` without `--mark`
3. If interactive: block with message suggesting the non-interactive alternative
4. If safe: approve

**Configuration:** `block_interactive` (default: `true`)

### 6. SessionStart: Nudge conflict-marker-style config (planned)

**Purpose:** Ensure `ui.conflict-marker-style = "git"` is set in the user's jj config
so Claude reads familiar 2-way git markers instead of jj's default 3-way format.

Currently the README documents this as a manual one-time command. This hook would
remove the manual step.

Options (in order of preference):

1. **Detect + nudge (recommended, conservative):** SessionStart hook checks
   `jj config list --user ui.conflict-marker-style`. If unset, emit a one-time
   note suggesting `jj config set --user ui.conflict-marker-style git` and how
   to opt out. Don't write the user's config without explicit consent.
2. **Auto-set with opt-out:** SessionStart hook runs `jj config set --user
   ui.conflict-marker-style git` unless `CLAUDE_PLUGIN_OPTION_set_conflict_marker_style`
   is `false`. Faster path to working state but modifies user config without
   per-install consent — only acceptable if the userConfig prompt at install time
   surfaces the intent and the prompt is actually shown (Claude Code's userConfig
   surfacing has been inconsistent in past versions — verify before relying on it).
3. **Repo-local set:** Write to `.jj/repo/config.toml` instead of user config.
   Scoped to one repo, but the file isn't tracked by jj so it's per-clone — every
   fresh clone of the same repo needs the setting reapplied. Not recommended.

Open questions for implementation:
- How does `jj config set --user` behave under a non-interactive Claude session?
  (Likely fine; it just writes a TOML key.)
- Should the nudge also recommend `ui.diff-instructions = false` to skip the
  3-way diff explainer that jj prints on `jj resolve`?
- Should the nudge no-op if the user has *explicitly* set the value to something
  other than `"git"` (i.e. they want jj's native format) vs. only nudging when
  unset? Detect-explicit-vs-unset isn't trivial via `jj config list`.

**Configuration:** `set_conflict_marker_style` (default behavior depends on
option chosen above)

## Plugin Configuration (userConfig)

```json
{
  "userConfig": {
    "auto_snapshot": {
      "description": "Auto-snapshot uncommitted work when Claude stops responding (true/false, default: true)"
    },
    "block_git": {
      "description": "Block git commands in jj repos (true/false, default: true)"
    },
    "block_interactive": {
      "description": "Block interactive jj commands like split (true/false, default: true)"
    },
    "session_state_inject": {
      "description": "Show jj status at session start (true/false, default: true)"
    },
    "diff_flag": {
      "description": "Flag for diff format: --git for unified, --stat for summary (default: --git)"
    },
    "set_conflict_marker_style": {
      "description": "Behavior for ui.conflict-marker-style nudge: 'nudge' (default — print a one-time suggestion if unset), 'auto' (set to 'git' on first SessionStart if unset), 'off' (do nothing)"
    }
  }
}
```

Each hook script reads its corresponding `CLAUDE_PLUGIN_OPTION_*` env var and exits
early (code 0, no-op) if the feature is disabled.

## What This Plugin Does NOT Cover

- **PR/bookmark push workflows** — too team-specific, better left to project CLAUDE.md
- **Workspace management** — useful but niche, can be added later
- **Colocated repo management** — edge case
- **Custom templates** — too jj-version-specific
- **Conventional Commits format** — commit message style is project-specific

## Testing Plan

1. **Rules:** Verify the rules file is loaded in every session and Claude follows the
   describe-and-snapshot workflow, uses `--git` for diffs, and avoids interactive commands.
2. **Skill auto-invocation:** Ask Claude to split a change, rebase, or recover from a
   mistake — verify it auto-invokes the correct skill and follows the recipe.
3. **Hook testing:** Verify each hook fires correctly:
   - Stop: create file changes, end session, verify auto-snapshot happened
   - PreToolUse(git): ask Claude to `git status`, verify it's blocked with helpful message
   - PreToolUse(jj interactive): ask Claude to split, verify block + alternative suggestion
   - SessionStart: start session in jj repo, verify state is injected
4. **Configuration:** Toggle each config option off, verify the corresponding hook becomes a no-op.
5. **Non-jj repos:** Verify all hooks gracefully no-op when not in a jj repo.
6. **jj version compatibility:** Test against jj 0.25+ (bookmark vs branch rename happened ~0.22; tested with 0.40).

