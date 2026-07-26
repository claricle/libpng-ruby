# 01 - CLAUDE.md update

- **Priority**: P0
- **Status**: Done

## Context

The agent-facing `CLAUDE.md` was out of sync after `encode_standard`,
the platform matrix expansion, and the architecture refactor. Future
Claude instances would land in a codebase that no longer matched the
documented structure.

## Approach

Re-created `CLAUDE.md` with:
- File-responsibility table for the new autoloaded structure
- Public API surface (encode / encode_standard / decode) with options
- FFI binding inventory (simplified + standard APIs)
- Ractor safety section including the Ruby 4.0 `#value` migration
- Code quality rules (no `require_relative`, no `send`, no `iv_get`,
  no `respond_to?` -- the project-wide rules)
- Spec inventory
- Cross-links to `TODO.roadmap/`, `CHANGELOG.md`, `REPORT-complex-api-needs.md`

## Delivered

PR #7 (this branch).
