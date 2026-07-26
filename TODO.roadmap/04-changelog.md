# 04 - CHANGELOG.md

- **Priority**: P1
- **Status**: Done

## Context

Release notes lived in PR descriptions and git tags -- invisible to
users tracking what changed between versions. The README's
`Versioning` section described the scheme but not what each release
actually delivered.

## Approach

New `CHANGELOG.md` following the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
format. Retroactively populated with entries for every released
version:

- 1.6.58.0 -- initial release
- 1.6.58.1 -- parsanol platform parity (musl, Windows ARM64, native arm64 runners)
- 1.6.58.2 -- encode_standard initial release
- 1.6.58.3 -- architecture refactor, encode_standard options
  (interlace/bit_depth/palette), read-side metadata, autoload+OOP

Each entry categorizes changes as Added / Changed / Fixed per Keep a
Changelog conventions.

The RubyGems `changelog_uri` metadata in `libpng.gemspec` already
points at `README.adoc#versioning`. Future: should it point at
`CHANGELOG.md` instead?

## Delivered

PR #7 (this branch).
