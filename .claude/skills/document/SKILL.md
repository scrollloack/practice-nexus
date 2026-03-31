---
name: document
description: Create a battle plan document in doc/battle-plan/ for a feature or topic
argument-hint: feature or topic description
disable-model-invocation: true
---

# Battle Plan

Create a structured battle plan document in `doc/battle-plan/` for: $ARGUMENTS

## Step 1 — Determine the filename

1. List all files in `doc/battle-plan/` using Glob
2. Find today's date in `YYYYMMDD` format from your system context (`currentDate`)
3. Find the highest `NN` sequence number across ALL existing files (regardless of date)
4. Increment by 1 — that is the new `NN` (zero-padded to 2 digits, e.g. `17`)
5. Convert the feature/topic name to `kebab-case`
6. Final filename: `YYYYMMDD-NN-kebab-case-title.md`

## Step 2 — Read context

Read 1-2 of the most recent battle plan files to internalize the current project state, patterns, and conventions. This ensures the AI Context block accurately reflects what already exists.

## Step 3 — Write the battle plan

Save the file to `doc/battle-plan/<filename>`. Follow this structure exactly:

````markdown
# NN — Feature Title (Human-Readable)

> **AI Context:** [One dense paragraph covering:
>
> - What the project already has (engines, patterns, infrastructure)
> - What this document adds (the delta)
> - Key conventions an AI must follow to apply these steps correctly
> - Any gotchas or non-obvious decisions]

---

## Concept: What We're Building

[Explain the feature conceptually — the problem it solves, the moving parts,
and how they relate. Include an ASCII diagram for any data flows or architecture.]

## New Patterns This Feature Introduces

| Pattern         | What it means              | Where you'll see it       |
| --------------- | -------------------------- | ------------------------- |
| **PatternName** | plain-language explanation | specific file or location |

> **Why [important decision]?**
> [Explain the reasoning.]

---

## Step NN.1 — [Action Title]

[What to do and why.]

```ruby
# filename: path/to/file.rb
# inline comments explaining non-obvious choices
code here
```

> **Why [X]?** [Brief rationale.]

## Step NN.2 — [Next Action]

[Continue for all steps needed end-to-end.]

---

## Verification Checklist

- [ ] [Concrete, runnable check]
- [ ] [Another verifiable outcome]

---

## Summary

| What                            | Where             |
| ------------------------------- | ----------------- |
| New file: `path/to/new_file.rb` | Brief description |
| Modified: `path/to/existing.rb` | What changed      |
| Migration: `rails db:migrate`   | When to run       |

### Style rules

- Steps are numbered `NN.M` (e.g. `16.1`, `16.2`) where `NN` is the document number
- Code blocks include the target filename as a comment on the first line
- `>` blockquotes are for "why" callouts — use whenever a decision might seem arbitrary
- ASCII diagrams in the Concept section for features with multiple interacting components
- Verification checklist contains only concrete, runnable checks
````

## Step 4 — Compatibility check

Re-read the 1-2 most recent battle plan files (from Step 2) and compare them against the new plan just written. Look for:

- **Breaking changes** — does the new feature remove, rename, or alter an interface, method signature, column, route, or contract that earlier plans depend on?
- **Backward compatibility** — does anything in the new plan require a migration strategy or versioning that wasn't accounted for?
- **Conflicting patterns** — does the new plan introduce a pattern that contradicts conventions established in recent plans?

If any issues are found, append a `## Compatibility Notes` section to the battle plan:

```markdown
## Compatibility Notes

> **Potential breaking changes identified:**

- [Description of conflict and which prior feature it affects]
- [Recommended mitigation or migration path]
```

If no issues are found, skip this section entirely — do not add a "no issues found" placeholder.

## Step 5 — Confirm

Tell the user the full path of the created file, the document number assigned, a one-sentence summary, and — if compatibility issues were found — a brief callout of what to watch out for.
