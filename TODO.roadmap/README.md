# TODO.roadmap

This directory holds the prioritized backlog for the libpng-ruby gem.
Each file is one work item with: priority, status, approach, and
(when done) the PR that delivered it.

Status legend:
- **Done** -- shipped
- **Planned** -- accepted, not yet scheduled
- **Won't do** -- explicitly rejected (with rationale)

Priority legend:
- **P0** -- critical correctness/safety
- **P1** -- quality improvements
- **P2** -- future features, low urgency
- **Future** -- waiting on external event (e.g. upstream libpng release)
- **Skip** -- intentional scope limit

## Index

| #  | Priority | Status   | Title |
|----|----------|----------|-------|
| 01 | P0       | Done     | [CLAUDE.md update](01-claude-md-update.md)
| 02 | P0       | Done     | [encode_standard Ractor spec](02-encode-standard-ractor-spec.md)
| 03 | P0       | Done     | [Bump mini_portile2 dependency](03-mini-portile2-bump.md)
| 04 | P1       | Done     | [CHANGELOG.md](04-changelog.md)
| 05 | P1       | Done     | [Benchmarks for encode paths](05-benchmarks.md)
| 06 | P1       | Done     | [Malformed input tests for decode](06-malformed-input-tests.md)
| 07 | P1       | Done     | [interlace: option on encode_standard](07-interlace-option.md)
| 08 | P2       | Done     | [Palette support](08-palette-support.md)
| 09 | P2       | Done     | [16-bit encode support](09-16-bit-encode.md)
| 10 | Future   | Planned  | [Libpng 1.6.59 bump when released](10-libpng-1.6.59-bump.md)
| 11 | P2       | Done     | [Read-side metadata getters](11-read-side-metadata.md)
| 12 | Skip     | Won't do | [Full libpng API surface binding](12-full-api-surface.md)
| 13 | Skip     | Won't do | [C extension wrapper for setjmp](13-c-extension-setjmp.md)
| 14 | Skip     | Won't do | [Progressive/streaming decode](14-progressive-decode.md)
| 15 | Skip     | Won't do | [File I/O variants](15-file-io-variants.md)
| 16 | P0       | Done     | [Architecture refactor: autoload + OOP](16-architecture-refactor.md)
| 17 | Future   | Planned  | [Ruby version support policy](17-ruby-version-policy.md)
| 18 | Future   | Planned  | [Dependabot for automated dependency bumps](18-dependabot.md)
| 19 | P2       | Planned  | [Text chunk (tEXt/zTXt/iTXt) read support](19-text-chunk-read.md)
| 20 | P2       | Planned  | [Color metadata read (gAMA/cHRM/sRGB/iCCP)](20-color-metadata-read.md)
