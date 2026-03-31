# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The role of this file is to describe common mistakes and confusion points that agents might encounter as they work in this project. If you ever encounter something in the project that surprises you, please alert the developer working with you and indicate that this is the case in the AgentMD or CLAUDE.md file to help prevent future agents from having the same issues.

## Prompt Shortcuts

### `(document)` — Write a Battle Plan

When a prompt includes `(document)`, create a battle plan file in `doc/battle-plan/` for the
feature or topic described in the rest of the prompt.

**Rules:**

- **Filename format:** `YYYYMMDD-NN-kebab-case-title.md` — use today's date, and increment `NN`
  from the highest existing number in the folder (e.g. if `15` is the last, use `16`).
- **AI-friendly header:** Start with a `> **AI Context:**` blockquote that summarizes the
  project state, what this document adds, and any key conventions an AI needs to apply the
  steps correctly.
- **Format:** Match the style of existing battle plan docs — concept explanation first, then
  numbered steps (`## Step N.M — Title`), runnable code blocks with inline comments,
  `>` blockquotes for "why" callouts, ASCII diagrams for data flows, and a summary table at the end.
- **Scope:** Cover the feature end-to-end: new files, changes to existing files, migration
  commands, and a verification checklist.

## Code Style

RuboCop is enforced. Key rules from `.rubocop.yml`:

- Max line length: 120 characters
- `frozen_string_literal: true` magic comment required on all files
- No documentation requirements for classes/modules
