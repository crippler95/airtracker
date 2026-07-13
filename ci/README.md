# CI workflows

These GitHub Actions workflows are kept here because the publishing token lacks the
`workflow` scope needed to push into `.github/workflows/`. To enable CI/releases,
move them into place and push (once, from an account with the `workflow` scope):

```bash
mkdir -p .github/workflows
git mv ci/ci.yml .github/workflows/ci.yml
git mv ci/release.yml .github/workflows/release.yml
git commit -m "Enable CI" && git push
```

- `ci.yml` — build + `swift test` on every push / PR (macOS).
- `release.yml` — on a `v*` tag: test, build the universal app, zip, publish a Release.
