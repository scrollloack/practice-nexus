# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The role of this file is to describe common mistakes and confusion points that agents might encounter as they work in this project. If you ever encounter something in the project that surprises you, please alert the developer working with you and indicate that this is the case in the AgentMD or CLAUDE.md file to help prevent future agents from having the same issues.

## Testing

Preferred test command: `bundle exec rspec`

## Code Style

RuboCop is enforced. Key rules from `.rubocop.yml`:

- Max line length: 120 characters
- `frozen_string_literal: true` magic comment required on all files
- No documentation requirements for classes/modules
