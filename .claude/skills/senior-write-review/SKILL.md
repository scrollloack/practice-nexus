---
name: senior-write-review
description: Use after completing a senior-level code review to save the findings as a structured markdown file in docs/code-review-issues/
---

# Save Senior Branch Review Findings

After completing a senior-level review of a branch, save the findings to a dated file in
`docs/code-review-issues/`.

## File Naming

```
docs/code-review-issues/YYYY-MM-DD-WOR-XXXX-<descriptive-name>.md
```

- `YYYY-MM-DD` — today's date
- `WOR-XXXX` — the Jira ticket number for the branch
- `<descriptive-name>` — short kebab-case summary of what was reviewed (e.g. `pay-code-sync-initial-implementation`)

## File Structure

```markdown
# Code Review: WOR-XXXX — <Feature Name>

**Branch:** `archieb/WOR-XXXX-vN`
**Date:** YYYY-MM-DD
**Reviewer:** Claude (senior-level review)

---

## Blocking Issues

### 1. <Issue title>

`path/to/file.rb:LINE` — Description of the problem, the failure scenario, and the fix.

---

## Significant Issues

### N. <Issue title>

Description.

---

## Minor Issues

### N. <Issue title>

Description.

---

## Future-Proofing Analysis

For any deferred behavior (WOR-XXXX NOTEs in the code), spell out what breaks when
that deferred work lands.

---

## Tests

Note any gaps in test coverage.

---

## Priority Summary

| Priority        | Issue |
| --------------- | ----- |
| **Blocking**    | ...   |
| **Significant** | ...   |
| **Minor**       | ...   |
```

## Rules

- Always include **Blocking**, **Significant**, and **Minor** sections — omit a section only if
  there are genuinely no findings in that category.
- Always end with a **Priority Summary** table.
- Always include a **Future-Proofing Analysis** section if any deferred behavior exists in the
  reviewed code (indicated by `WOR-XXXX` NOTEs or commented-out code).
- Reference file paths with line numbers: `app/models/payrules_service/pay_code.rb:5`
- Do not summarise the diff — describe the problem and its consequence.
