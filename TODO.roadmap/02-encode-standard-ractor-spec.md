# 02 - encode_standard Ractor spec

- **Priority**: P0
- **Status**: Done

## Context

PR #6 added `encode_standard` and claimed Ractor safety (every call
allocates its own `png_struct`), but only `encode` and `decode` had
Ractor specs. Unverified claims are worse than no claims.

## Approach

New spec file `spec/ractor_standard_spec.rb` with two cases:
1. Encode inside a Ractor, round-trip the bytes in the main Ractor.
2. 8 concurrent Ractors running `encode_standard(filter: :sub)` and
   verifying decode round-trip.

Uses the `ractor_result(ractor)` helper (prefers `#value` on Ruby 4.0+,
falls back to `#take` on Ruby 3.x).

## Delivered

PR #7 (this branch).
