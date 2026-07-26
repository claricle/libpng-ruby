# 18 - Dependabot for automated dependency bumps

- **Priority**: Future
- **Status**: Planned

## Context

The gem has runtime dependencies on `ffi` and `mini_portile2`, and dev
dependencies on `rake`, `rspec`, and `rubocop`. These are bumped
manually when someone notices a new version. Dependabot would automate
this and open PRs when new versions are released.

## Proposal

Add `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    groups:
      dev-deps:
        dependency-type: "development"
      runtime-deps:
        dependency-type: "production"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

Two groups:
- **dev-deps**: rake, rspec, rubocop -- batch into one PR per week
- **runtime-deps**: ffi, mini_portile2 -- separate PRs (more careful
  review since these affect end users)

Plus GitHub Actions version bumps (checkout, upload-artifact, etc.).

## Risks

- Slightly noisier PR queue.
- Some bumps may break CI (e.g. rubocop new cops). Auto-merge is not
  appropriate; each PR needs human review.

## Trigger

When the project stabilizes after the current refactor wave.
