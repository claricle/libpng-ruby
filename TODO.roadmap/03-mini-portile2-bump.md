# 03 - Bump mini_portile2 dependency

- **Priority**: P0
- **Status**: Done

## Context

The gemspec constrained `mini_portile2` to `~> 2.6`. Current upstream
is 2.8.9. The constraint prevented the source gem from picking up
mini_portile2 bug fixes and CMake improvements.

## Approach

Bumped `libpng.gemspec`:

```ruby
spec.add_dependency 'mini_portile2', '~> 2.8'
```

Allowed versions 2.8.x. Did not jump to `>= 2.8` (unbounded) because
mini_portile2 has had breaking changes between major versions in the
past; staying on `~> 2.8` is the conservative choice.

## Delivered

PR #7 (this branch).
