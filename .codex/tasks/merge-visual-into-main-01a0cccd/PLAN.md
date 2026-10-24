# Merge visual upgrade into main

- Task-ID: merge-visual-into-main-01a0cccd
- Owner-Session: 01a0cccd-aa02-71c0-b47f-62c695c0dee1

## Objective
Finish the in-progress merge of `codex/sanqian-visual-upgrade` into `main`, preserving main's recognition/OCR safety gates, passing the Flutter regression suite, and creating the merge commit without adding the main worktree's unrelated `.codex/` evidence directory.

## Steps
1. Reconcile ImportReview and related import screens: retain main recognition/OCR behavior and restore compatible visual polish.
2. Reconcile week picker semantics and any layout-sensitive tests without removing main functionality.
3. Run targeted tests, then the full Flutter test suite with the repository toolchain.
4. Verify no unresolved conflicts, staged diff checks, or unrelated `.codex/` files; commit the merge.
