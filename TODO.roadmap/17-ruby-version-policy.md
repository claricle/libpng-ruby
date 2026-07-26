# 17 - Ruby version support policy

- **Priority**: Future
- **Status**: Planned

## Context

The gemspec declares `required_ruby_version = '>= 2.7.0'`. Ruby 2.7
reached EOL in March 2023. Ruby 3.0 reached EOL in March 2024. Ruby
3.1 is in security maintenance. Ruby 3.2, 3.3, 3.4 are current.

Ractors require Ruby 3.0+. Our Ractor specs guard with
`return unless defined?(Ractor)` so they no-op on 2.7, but the
`return` at file top-level might warn on some Ruby versions.

## Proposal

Bump `required_ruby_version` to `>= 3.1.0` in a future minor release.

Rationale:
- Drops EOL versions (2.7, 3.0) -- no security backports
- Keeps 3.1 (security maintenance) and all current versions (3.2, 3.3, 3.4)
- Aligns with `mini_portile2 ~> 2.8` which also requires 3.1+
- Removes the `return unless defined?(Ractor)` guard from spec files
  (the gem can assume Ractor exists)

## Risks

- Some users may still be on 2.7 (legacy deployments). They'd be
  stuck on the last 2.7-compatible release.
- RubyInstaller ARM64 builds start at 3.4.1, so Windows ARM64 users
  are unaffected.

## Approach

1. Wait one release cycle after announcing the deprecation.
2. Bump `required_ruby_version` in `libpng.gemspec`.
3. Update the README Ruby version badge.
4. Remove the Ractor guard in `spec/ractor_spec.rb` and
   `spec/ractor_standard_spec.rb`.

## Trigger

Either:
- ruby-setup-ruby drops 2.7 and 3.0 from its version matrix, OR
- A security feature in libpng requires Ruby 3.1+ APIs.
