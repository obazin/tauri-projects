---
description: Branch from the default branch for a GitHub issue, plan it, implement it with atomic commits following every CLAUDE.md rule, then loop through code review until it passes clean.
argument-hint: '#<issue-number>  (e.g. /implement-issue #42)'
---

# /implement-issue — implement a GitHub issue end-to-end

Take the GitHub issue passed in `$ARGUMENTS` (a number with a leading `#`, e.g. `#42`), implement everything required to close it on a dedicated branch, commit each step atomically, and don't stop until a code review of the change passes with no actionable findings.

## 0. Resolve the issue

- Strip the leading `#` from `$ARGUMENTS` to get the bare number. If no number was passed, stop and ask for one.
- Read it fully: `gh issue view <number> --comments`. Read the body and every comment — acceptance criteria and clarifications often live in the discussion.
- Follow every reference the issue makes — linked issues/PRs (`gh issue view` / `gh pr view`), file paths (Read) and any figma.com link (Figma MCP) — until you understand the complete scope.
- Restate, in 2–3 sentences, what "done" means for this issue. If the issue is ambiguous or under-specified, use `AskUserQuestion` to resolve it **before** branching — do not guess at scope.

## 1. Create the working branch (do this first)

- Confirm a clean working tree: `git status --short`. If there are uncommitted changes, **stop and ask** — don't branch over the user's in-progress work.
- Find the base branch: the one CLAUDE.md names for feature work, otherwise the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`).
- Branch off it, naming the branch after the issue: `git switch -c issue-<number>-<short-kebab-slug> <base>` (slug = ~3–5 words from the issue title).
- All subsequent work happens on this branch.

## 2. Plan (mandatory — enter plan mode)

- Enter plan mode (`EnterPlanMode`). Investigate the codebase read-only: find the components, stores, IPC commands and docs the issue touches, and follow any how-to recipes in `docs/`.
- Break the work into **discrete, independently-committable steps** — these become your atomic commits in §4.
- Name the tooling the work needs (see §3) in the plan.
- Present the plan with `ExitPlanMode` and wait for approval. **Do not edit any file before the plan is approved.**

## 3. Load the right tools up front

| If the work involves…                                         | Use                                                                   |
| ------------------------------------------------------------- | --------------------------------------------------------------------- |
| Svelte 5, Tauri v2 or other library APIs                      | `mcp__svelte__get-documentation` / context7 (live docs, not memory)   |
| Any `.svelte` edit                                            | `mcp__svelte__svelte-autofixer` after each edit, loop until clean     |
| Any IPC-surface edit (command, registration, capabilities)    | `rust-ipc-reviewer` agent after the edit                              |
| Per-OS behaviour                                              | `cargo check --target <triple>` for every shipped triple              |
| A figma.com link                                              | The Figma MCP and its skills                                          |

## 4. Implement — one atomic commit per step, every CLAUDE.md rule applies

Track the work with one task per step from the approved plan.

- Complete a single step, get it green, then commit _just that step_ before starting the next. Don't batch steps, and never leave one half-committed.
- "Green" before each commit: `svelte-autofixer` clean on every touched `.svelte` file and the project's checks passing (CLAUDE.md rule 9).
- Stage only the files for that step (name them explicitly — no `git add -A`).
- Commit messages follow the repository's existing convention (read `git log` first) and reference the issue.
- Update the docs for any user-facing change, in the commit it documents.

## 5. Review loop — repeat until the review is clean

1. Run `/code-review high` on the branch's changes.
2. Triage every finding. Fix all correctness bugs and every valid quality finding. If you disagree with a finding, state why instead of silently skipping it.
3. Re-run `svelte-autofixer` on any `.svelte` file you touched, then the project's checks.
4. Commit the fixes as their own atomic commit.
5. Re-run `/code-review high`, and repeat until a full pass reports **no actionable findings**. That is the only acceptable exit condition.

## 6. Finish

- Confirm the tree is fully committed: `git status` is clean and `git log --oneline <base>..HEAD` lists one clean commit per step.
- Summarize for the user: the branch name, the commit list, and how the change satisfies the issue's "done" definition.
- **Do not push or open a PR** unless the user explicitly asks.
