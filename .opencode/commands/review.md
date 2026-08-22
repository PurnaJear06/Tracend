---
description: Review the current working-tree diff against AGENTS.md rules (read-only reviewer agent)
agent: reviewer
subtask: true
---

Review the current uncommitted changes in this repository.

Current state:
!`git status --short`

Diff summary:
!`git diff --stat`

Staged summary:
!`git diff --cached --stat`

Follow your full process: read AGENTS.md, inspect the diff file by file, run the checklist,
and write findings to `docs/reviews/` with today's date. Report the findings file path and
the verdict when done.
