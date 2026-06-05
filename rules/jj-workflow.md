# Jujutsu (jj) Workflow

When the project uses jj (`.jj/` exists at the repo root — `jj root` confirms),
use jj — never git. The rules below cover the patterns Claude gets wrong most often.

## Core Rules

- Use jujutsu (jj) commands for version control, never git
- Always use `--git` flag when viewing diffs for standard unified diff format:
  - `jj diff --git` to inspect WIP commit diff
  - `jj show --git` to review specific commits
  - Without `--git`, jj uses an inline format that can be confusing

## Jujutsu Commit Management

- **Context:** Before editing commits (squashing / editing description / etc.), identify the
  changes to reference by checking the current state (`jj status` / `jj log` / etc.)
- **New work on a fresh change:** Before starting a new task (editing files), check `jj log -r @`
  to see if the current change already has a description. If it does, run `jj new` first so you
  don't accidentally mix unrelated edits into a completed change.
  - **`jj describe` ends the current change.** After describing a commit, the next edit goes in
    a new change — run `jj new` immediately, before any tool that writes files. This applies even
    when the next edit is in direct response to user feedback on the just-described change (e.g.
    "actually, also do X"). If "X" is a tweak to the same concept, you can `jj squash` afterward;
    if it's a new concern, it stays separate. Default to `jj new` first, decide later.
  - **Pre-flight check before `Edit`/`Write`:** if `jj log -r @` shows a description, your edit
    will accumulate into that described commit. Run `jj new` unless you specifically intend to
    amend.
- **Squashing changes:** Use `jj squash --into <commit_id> -m "message"` to combine current changes
  into a target commit with a new message.
  - **`--from`/`--into` semantics:** `--from A --into B` takes A's diff (relative to A's parent) and
    applies it into B. If B already *reverses* A's changes, the squash will re-add them — the two
    diffs don't cancel out. When a later commit supersedes an earlier one (adds then removes the same
    thing), just `jj abandon` the earlier commit instead of squashing.
- **Editing descriptions:** Before running `jj describe -m` on an existing commit, read the current
  description first (`jj show -s -r <rev>` — shows the full description with a file summary,
  unlike `jj log` which truncates) so you don't accidentally drop details from a previous
  description. This applies to both `jj describe` and `jj squash --into ... -m`.
- **Multi-line descriptions:** Feed the message via stdin to avoid the autonomous-bash
  hassle of quoting multi-line `-m` arguments (every unique multi-line command tends to
  trigger a fresh permission prompt in scripted Claude Code workflows). Two patterns:
  - **Short messages:** `printf '%s\n' 'subject' '' 'body line 1' 'body line 2' | jj describe --stdin`.
    Each arg is one verbatim line; `''` makes a blank line. No `\n`/`\\` escaping needed.
  - **Long messages or messages with single quotes / awkward characters:** Write the message
    to `$TMPDIR/jj-msg.tmp` via the Write tool, then `jj describe --stdin < $TMPDIR/jj-msg.tmp`.
    `$TMPDIR` is sandbox-writable and lives outside the project tree, so jj won't snapshot it
    and no `.gitignore` edit is needed. Don't put this scratch file under `.claude/` — writes
    there trigger an "agent editing its own settings" permission prompt. Don't use bare `/tmp/`
    either — it triggers stricter sandbox permission prompts. Leave the file on disk; the next
    multi-line message overwrites it. Don't `rm` it — that triggers a permission prompt for no
    benefit.
- **Splitting changes:** If a commit touches independent concerns (e.g. a bug fix + a test helper
  improvement + an infra change), split it into focused commits. Use `jj split -r <rev> -m "message
  for selected" -- <filesets>` to select files for the first commit; the rest go into a child commit.
  Then `jj describe` the child.
  - **Split before dropping:** When a commit has some obsolete changes mixed with useful ones,
    split off the useful parts first, then abandon only the obsolete remainder. Never drop an
    entire commit without checking all its contents.
  - **Splitting hunks within shared files (when `jj split` won't work):** If the changes you want
    to split out overlap the same hunks/lines as the rest (so `jj split -- <files>` can't separate
    them), use the **restore-pivot** trick. The two state hashes you need are easy to find in
    `jj op log` — every `squash` op shows `into <hash>` (the pre-squash state) and creates a new
    post-squash hash visible in subsequent ops. To split commit `C` (currently in post-state) into
    a parent at pre-state and a child with just the post diff:
    ```
    jj edit C
    jj restore --from <pre-state-hash>   # C now holds only the original content
    jj new
    jj restore --from <post-state-hash>  # child now holds only the layered-on diff
    jj describe -m "..."
    ```
    Cleaner than `jj op revert` for this case — revert chains across overlapping squashes create
    conflicts; restore-pivot doesn't because each `restore` writes a known-good tree.
- **Snapshot often:** `jj describe` the current state with a clear message, then `jj new` to start
  fresh on top. Do this frequently — before switching approaches, after getting something working,
  before experimenting, etc. Multiple snapshots in a chain are fine; squash them later to consolidate.
  If a change doesn't work out, `jj abandon` to get back to the last working snapshot.
- **Replacing an approach:** When pivoting to a different approach for the same problem, don't modify
  the existing commit. Leave it as-is (as a fallback) and use `jj new <parent>` to start a new
  commit from the appropriate ancestor (often `@-`, but pick the right base). This way both
  approaches are preserved and either can be abandoned later.
- **`jj rebase` — `-s` is almost always what you want, not `-r`.** The flags select *which*
  revisions move, not where they go (that's `-d`/`-A`/`-B`):
  - `-s REV -d DEST` moves REV *and all its descendants* as a chain onto DEST. This matches
    the git-rebase mental model — "move this commit and everything on top of it onto the new
    base" — and is the right default when you want a sub-chain relocated.
  - `-r REV -d DEST` moves ONLY that one revision. jj fills the hole by re-parenting REV's
    descendants onto REV's *original* parent, so they stay in the old chain location while REV
    lands alone at DEST. If those descendants depended on REV's changes, they now conflict or
    silently lose that dependency. Use only when deliberately hoisting a single commit out of
    its chain.
  - `-b REV -d DEST` moves the whole "branch" containing REV (revset `(DEST..REV)::`),
    including siblings of REV's chain. Useful when you want everything between a base and a
    tip rebased together.
  Reach for `-s` unless you specifically want one of the other behaviors.
- **Side commits while a change is WIP:** When you're mid-way through a WIP change in `@` and want
  to land an independent smaller change (a doc fix, a typo, an unrelated cleanup) as its own commit,
  don't mix it into the WIP. Insert it as a *parent*: `jj new -B @` (`--insert-before`) creates a
  new empty change before `@` — jj snapshots the WIP into its own commit and rebases it intact onto
  the new change, so nothing is lost. Make the side edits in the new change, `jj describe` it, then
  `jj edit <wip-change-id>` to resume the WIP. The side commit lands below the WIP in the chain —
  independently reviewable and landable — and the WIP keeps building on top of it. Prefer this over
  stashing the WIP or interleaving unrelated edits into one change.
- **Testing the baseline without your WIP change — never hand-revert.** When you need to
  build/test the code *without* the in-progress edits sitting in `@` — most commonly to
  reproduce a bug before applying your fix, or to A/B two behaviors — do NOT manually undo the
  edits with the editor and re-apply them later. That risks losing the work and is wasted
  motion. Instead `jj new @-` to start a temporary sibling change off the parent: jj snapshots
  the WIP into its own commit first, and the new empty sibling has none of it. Build and test on
  the sibling, then `jj edit <wip-change-id>` to return to the WIP intact. The WIP and the
  baseline are now two siblings of the same parent; `jj abandon` the throwaway sibling when
  done. If you already hand-reverted before remembering this, the WIP isn't lost — jj snapshotted
  it on the `jj` command that ran right after the edit; find that commit in `jj op log`
  (`jj op show <op> --git` to confirm it has the change) and `jj restore --from <hash> -- <paths>`
  it into a fresh change.
- **`jj absorb` can over-absorb.** It auto-distributes working copy changes into ancestor
  commits by matching changed lines to the commit that last touched them. This is dangerous
  when you *intentionally* have "before" and "after" commits touching the same lines (e.g.,
  a doc commit that introduces red rows, then a trailing commit that flips them to green).
  Absorb will collapse the "after" changes into the "before" commit, destroying the narrative.
  Use targeted `jj squash --into <rev> -- <file>` instead when you need changes to land in a
  specific commit without leaking into others.
- **Undoing operations:** NEVER use `jj op restore` — it appends a new op that resets the repo
  state to the target, abandoning every operation made since (including snapshots from other
  workspaces, so peers' uncommitted work disappears). Always use `jj op revert <op_id>` instead,
  which appends a new op that inverses only the target op while preserving everything else
  in the log. (The op log itself is append-only either way — both commands add to it.)
  Prefer `jj op revert` over `jj undo` even for the most recent op — the former takes an
  explicit op id (which
  forces you to look at `jj op log` first and pick the right target), while `jj undo` blindly
  reverts the latest op, which is risky when several recent ops are intermingled snapshots from
  tool calls and editor saves.
  - **Before reverting a non-most-recent op, check `jj log --at-op <op>` first.** Reverting an op
    that touched a commit other workspaces could plausibly have built on top of (or snapshotted as
    their `@`) doesn't warn you — but their work post-that-op gets hidden when you then operate on
    the reverted state. The fix-after-the-fact is what the peer does (find the hidden hash via
    `jj op show --git --patch` on the snapshot ops in their op log, then `jj restore --from <hash>`),
    but you can prevent the disruption by previewing cross-workspace state first.
- **Inspecting an op's contents:** `jj op log` shows only the operation type and command args
  (e.g. "snapshot working copy"), not the diff. Before reverting any op, run `jj op show <op_id>
  --git --patch` to see exactly which commits and files changed. Especially important after a
  series of small edits — multiple consecutive `snapshot working copy` ops can each contain
  unrelated changes, and reverting blindly may revert the wrong thing or revert good edits along
  with bad ones. Audit each op's actual diff first, then revert the specific ones you want to
  undo.
- **Peer-workspace WIP looks identical to your own in `jj log`.** When you run multiple jj
  workspaces against one repo, each workspace's working-copy snapshot is a commit in the shared
  op history — it appears in `jj log` from any workspace as a bare auto-generated 2-letter-prefix
  change ID (`yy`, `kr`, `ox`, etc.), sitting in the visible head set, indistinguishable from your
  own empty WIP changes. The workspace field is only visible in `jj op log`, not `jj log`. **Before
  `jj abandon` of any commit you didn't explicitly create in the current turn, run `jj show
  <change> --git` and confirm both the content and the snapshot op's workspace metadata in
  `jj op log`.** Generic 2-letter prefixes are almost always auto-generated WIP; semantic prefixes
  you set deliberately look different. If you abandon a peer's `@`-pointed snapshot, their
  unsnapshotted edits get reconciled away on their next `jj` command — they have to recover via
  `jj op show --git --patch` on snapshot ops + `jj restore --from <hidden-hash>`. Same caution
  applies even when you "noticed" the change ID earlier and reasoned it was peer activity:
  rationalizing it as cleanup later is the failure mode.
- **Verifying complex operations:** Before starting multi-step commit manipulation, record the
  end-state commit hash (e.g. `jj log -r <tip>` to get the hash). After each major step, verify
  with `jj diff --git --from <known_good_hash> --to <current_rev>` — an empty diff confirms
  the manipulation preserved the exact end state; a non-empty diff should be reviewed to
  confirm only intentional changes remain (e.g. cleaned up debug logging or fixed stale
  comments). Catching problems early is cheaper than undoing a long chain. If no pre-recorded
  hash exists, use `jj op log` and `jj --at-op <op_id> log -r <rev>` to find one
  retroactively.
- **Finding authorship:** Use `jj file annotate <path>` (not `jj log -p`) to trace who wrote
  each line and in which commit. Useful for understanding why code was written a certain way
  before changing it.

## Small, Focused Commits

Each commit should be **one self-contained change** — a single bug fix, a single refactor, or one
slice of a feature. Small commits are easier to review, less risky, simpler to roll back, and
produce clearer history. A good signal: if the commit message needs "and" or "also" to describe what it does, it's
probably too big.

The test for one commit vs. two: split when each part is independently meaningful — reviewable and
revertable on its own; combine when one part only makes sense as a description or enabler of the
other.

**Belongs together:** implementation + its tests; code + the doc/comment that only describes *that*
code (revert the code and the doc is now wrong). **Should be separate:** refactors vs. bug fixes,
different layers/subsystems. **Docs/config are the trap — decide per change, don't assume a
direction:** a README/changelog/doc-comment tied to the code you just changed goes *with* it; a
standalone note (e.g. a gotcha true regardless of how the fix is written) goes separate.

**Separate by default.** Even small follow-up fixes (typos, missed renames, header tweaks) should
default to their own commit. This keeps each change independently reviewable, revertable, and
abandonable. Squashing is fine when appropriate — just don't assume small fixes belong in a
previous commit.

**Splitting the working copy by file:** When the working copy contains changes for multiple
unrelated commits and the changes don't overlap within a single file, the autonomous-friendly
pattern is two commands:

```
jj describe --stdin < $TMPDIR/jj-msg.tmp  # set description on @ via stdin
JJ_EDITOR=true jj commit <files>          # finalize @ with that description
                                          # the rest moves to a new empty child @
```

`jj describe --stdin` avoids the autonomous-bash hassle of passing a multi-line `-m` argument.
`JJ_EDITOR=true` is required because `jj commit <files>` always opens an editor on the
*just-committed* commit's description — pre-filled with whatever you set on `@` first, but
opened nonetheless. A no-op editor accepts the pre-filled description verbatim so the command
can complete non-interactively. After it runs, the leftover diff is in a fresh undescribed
working copy, ready for the next round.

`jj commit -m "..."  <files>` looks tempting but a) the multi-line message has to be inlined,
which fights autonomous-bash constraints around `$(...)` and newlines, and b) it still opens
the editor on the just-committed commit's description re-edit, so you'd need `JJ_EDITOR=true`
anyway.

`jj split -- <files>` works too but requires descriptions for *both* halves and so needs more
plumbing. Prefer the describe + commit pattern unless you specifically want both sides of
the split described up front.

For separating hunks *within* the same file, the interactive `jj split` flow needs a TUI
(not available in autonomous mode); use the restore-pivot trick documented above instead,
or revert/re-apply the unwanted hunks via Edit before committing.

## Cleaning Up Commit Chains

When the user asks to clean up / reorder / squash a chain of commits:

- **Don't over-combine.** Each commit should be independently useful. Keep fixes, refactors,
  test changes, and infra changes as separate commits unless they are truly incomplete without
  each other (e.g. two halves of the same fix where neither works alone).
- **Never combine fixes into refactors.** A bug fix and a refactoring of the same area are
  separate concerns — keep them in separate commits even if they touch the same file.
- **Squash direction:** Squash the later commit into the earlier one (`jj squash --from <later>
  --into <earlier>`), not the other way around, to preserve the chain order.
- **After squashing, verify the description.** Check that the squashed commit's message captures
  everything from both original descriptions. Ask the user if unsure.
- **Prefer rebase+squash over abandon for obsolete changes.** `jj abandon` of a mid-chain
  commit creates conflicts in descendants that restored what the abandoned commit removed.
  Instead: rebase the obsolete commit adjacent to its counterpart, then squash them together
  so the changes cancel out cleanly.
- **Propose reordering conservatively.** Only reorder commits that touch different files.
  If commits modify the same file, reordering will likely conflict. When unsure, try it —
  reverting the op is cheap — but don't chain multiple risky rebases before checking for
  conflicts.
- **After manipulation, check for stale artifacts.** Squashing or reordering can leave behind
  stale comments, inaccurate commit descriptions, or debug logging that should be cleaned up.
  Scan for these and squash fixes into the relevant commit.

## General Tips

- **Never suppress jj errors:** Don't use `2>/dev/null` on jj commands. Hidden errors (like
  ambiguous change ID prefixes) lead to wrong assumptions. Always let stderr through.
- **Finding commits:** Change ID prefixes grow longer as new changes are created (`qw` → `qwn`).
  Don't cache old short prefixes — always use the full prefix from the latest `jj log` output.
  To find commits by description: `jj log -r 'description(substring:"keyword")'` — but this
  only searches the default revset (recent/mutable revisions). To search immutable ancestors
  too, use `jj log -r '::@ & description(substring:"keyword")'`. (A bare string like
  `description("keyword")` is parsed as a *glob* pattern with no wildcards — i.e. exact
  match — so it almost never matches what you want. Use `substring:`, or wrap with `*`s for
  glob.) To see all recent work: `jj log -r "all()" --limit 40`.
- **Recognize change IDs in conversation.** When the user mentions a short lowercase alphabetic
  token (`vx`, `nvp`, `kqr`, `st`, etc.) in passing — especially near words like "commit", "change",
  `jj`, `rebase`, `new`, `squash`, "branch", "parent", "off of" — treat it as a jj change ID
  prefix and resolve it with `jj log -r <prefix>` before assuming it's a typo, placeholder,
  or unrelated jargon. Example: "`jj new` off of vx if we're keeping that commit" means `vx`
  is a literal change ID to look up, not a placeholder.
- **`(hidden)` after a rewrite doesn't mean "abandoned" — it means "rewritten."**
  After `jj rebase`, `jj squash`, `jj edit`, etc., the original commit hash is hidden
  because that specific snapshot is no longer reachable, but the change ID still resolves
  to the rewritten version at a new hash. **Always refer to post-rewrite commits by
  change ID** (or by searching descriptions in a *fresh* `jj log`), never by the
  pre-rewrite hash. Two failure modes this prevents:
  - **Reading:** treating a `(hidden)` line in `jj log` as "the chain got abandoned" and
    proposing to restore it, when it's actually sitting on main under new hashes. Find
    it with `jj log -r '::main & description(substring:"keyword")'`.
  - **Mutating:** `jj describe <old-hash>` or `jj squash --into <old-hash>` resolves
    the hash to the hidden snapshot and creates a *divergent* parallel rewrite — leaving
    two visible commits at the same change ID and silently discarding in-flight content
    from the live chain. Especially insidious when chaining `squash` then `describe` to
    update a commit's message: the squash succeeds, the describe appears to succeed, and
    the on-disk file state can snap back to the pre-squash version. Use
    `jj describe <changeid>` / `jj squash --into <changeid>` instead.
- **`--limit` on a search can hide what you're looking for.** If you're trying to confirm
  "is commit X on main?", don't search a `jj log -r "::main" --limit 40` listing — your
  commit may simply be older than the cutoff. Either grep an unbounded `jj log -r "::main"`,
  or use `jj log -r '::main & description(substring:"X")'` (no limit needed because the
  revset itself filters).

