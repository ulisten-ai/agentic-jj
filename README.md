# agentic-jj

Jujutsu (jj) workflow rules for AI coding agents. Currently ships as a Claude Code
plugin; the rules themselves are tool-agnostic and future versions will package
them for other agent harnesses (OpenAI Codex, etc.).

## What it addresses

Most jj plugins for AI agents are on-demand skills, or read like jj
documentation adapted for an agent — restating what models already know
from training. This one loads as always-on rules into Claude's context,
and addresses two specific things Claude needs help with:

**1. Resistance to the failure modes that show up when an LLM drives jj
autonomously** — editor prompts that hang the session, multi-line `-m` quoting
headaches, `--from`/`--into` squash surprises, `jj op restore` clobbering work
from concurrent jj workspaces (e.g. parallel Claude Code sessions in the same
repo), revset-syntax pitfalls, and so on.

**2. A workflow shape to follow.** Claude needs one to use jj effectively —
without explicit guidance, jj's flexibility (multiple ways to checkpoint,
clean up, recover) becomes a source of inconsistency. The shape this plugin
teaches:

- **Small, focused commits** — default to separate, not combine.
- **Snapshot-often, squash-later** — many intermediate commits while working;
  consolidate when verified.
- **Aggressive history rewriting** — history is malleable until push.
- **Describe early** — set a description as soon as the change has a clear
  concept, not at the end.

If you have a different working style in mind, adapt the relevant rules into
your own setup instead of installing wholesale.

PR-review workflow is out of scope — supplement separately if needed.

## Install

```
/plugin marketplace add ulisten-ai/agentic-jj
/plugin install agentic-jj
```

The rules take effect in **new Claude Code sessions** after install — the
`SessionStart` hook can't fire retroactively in the session you ran the install
command from, so restart Claude Code (or open a fresh session) to see the rules
load.

## Recommended one-time jj config

Run once after install:

```
jj config set --user ui.conflict-marker-style git
```

This changes the conflict markers jj writes into your working copy from its
default 3-way `<<<<<<<` / `%%%%%%%` / `+++++++` / `>>>>>>>` format (which
encodes the base + each side's diff) to git's familiar 2-way
`<<<<<<<` / `=======` / `>>>>>>>` format. LLMs are heavily trained on the
git format and read it more reliably; jj's 3-way format is information-richer
but unfamiliar to most models. The setting is local to your working copy —
it doesn't affect what's stored in the repo or what collaborators see.

## How it works

On every `SessionStart`, a hook script syncs the rules file to
`<project>/.claude/rules/ulisten/agentic-jj/jj-workflow.local.md`. Claude Code auto-loads
every `.md` under `<project>/.claude/rules/` recursively into the session's primary
context window — so the rules are always-on within the project, but scoped to it (no
global `~/.claude/rules/` pollution).

The destination uses the `.local.md` suffix to piggyback on the common `*.local.md`
gitignore convention; if your project's `.gitignore` doesn't cover it yet, the hook
appends `*.local.md` once. Idempotent on every run.

## What's covered

The rules file (~265 lines) covers:

- **Mental model** — the working copy IS a change; change ID vs commit hash; the op log
- **Non-interactive commands** — alternatives to forms that open editors and hang the session
- **Snapshot workflow** — when to `jj new`, when to `jj describe`, how often to checkpoint
- **Squash semantics** — `--from`/`--into` directionality, when diffs don't cancel out
- **Splitting changes** — file-based via `jj split -- <files>`, restore-pivot for hunks
- **Revsets** — correct `description(substring:"...")` syntax (bare strings are glob, not substring); common patterns
- **Op log & recovery** — `jj op revert` over `jj op restore`; concurrent-workspace caution
- **Multi-line commit messages** — `printf '%s\n' ... | jj describe --stdin` or `$TMPDIR/jj-msg.tmp`
- **Small-focused-commits philosophy** + the `JJ_EDITOR=true jj commit <files>` working-copy-split pattern
- **General tips** — no stderr suppression, change ID conversational recognition, `(hidden)` vs `abandoned`, `--limit` gotchas

## Requirements

- Claude Code 2.x (plugin system)
- jj 0.25+ recommended (tested with 0.40)

## Roadmap

v0 ships rules only. Planned for later versions:

- **Skills** for on-demand complex recipes: `jj-split`, `jj-rewrite-history`, `jj-recovery`
- **Safety hooks**: block-git (in jj repos), check-interactive (intercept editor-opening jj commands), auto-snapshot (preserve work on session stop), inject-state (show `jj status` at session start)
