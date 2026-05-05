# Release Process

Every delivery to the customer (merge to `staging`) is a release and receives a new version number. Merges to `main` confirm the release as the production state. Merges to `development` can optionally already receive a pre-release version.

---

## When Is a Release Created?

| Merge Target    | Release Required | Version Suffix | Meaning                                          |
|:----------------|:-----------------|:---------------|:-------------------------------------------------|
| `development`   | Optional         | `-dev`         | Internal pre-release for team testing            |
| `staging`       | **Required**     | none           | Release candidate, delivery for customer sign-off |
| `main`          | **Required**     | none           | Final production release (same version)          |

**Ground rule:** Every delivery to the customer is its own release. Before a PR from `development` to `staging` is opened, the version number must be bumped and the CHANGELOG must be updated.

---

## Versioning Strategy (SemVer)

We follow [Semantic Versioning 2.0.0](https://semver.org/):

| Type | Schema | When? |
|---|---|---|
| **MAJOR** | `X.0.0` | Breaking changes: infrastructure restructuring, changed configuration formats, migration required |
| **MINOR** | `0.Y.0` | New features, new apps, architectural improvements (backwards-compatible) |
| **PATCH** | `0.0.Z` | Bug fixes, typos, minor corrections |

### Decision Guide

```
Do existing installations need to be manually adjusted?
  Yes → MAJOR

Is new functionality being added (without migration effort)?
  Yes → MINOR

Only a bug fixed?
  Yes → PATCH
```

When in doubt, be conservative: prefer MINOR over PATCH, prefer MAJOR over MINOR.

---

## Release Process Step by Step

### On Merge to `development` (optional)

A pre-release tag can be set when the state is considered internally testable. This is not a formal customer release.

- [ ] Determine version number (e.g. `v1.2.0-dev`)
- [ ] Update CHANGELOG with `[Unreleased]` entry or dev entry
- [ ] Set and push tag:

```bash
git tag v1.2.0-dev -m "Dev state: <short summary>"
git push origin v1.2.0-dev
```

---

### On PR to `staging` (required)

This step creates the formal release for customer acceptance. The version number is set on `development` **before the PR**.

#### 1. Determine Version Number

Determine the new version based on the changes since the last release (see SemVer table above).

#### 2. Update CHANGELOG

Add a new section to `CHANGELOG.md`:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Breaking Changes (MAJOR only)
- ...
- Migration guide: ...
```

#### 3. Set Tag on `development`

```bash
git checkout development
git pull origin development

# Set tag
git tag vX.Y.Z -m "Release vX.Y.Z: <short summary>"

# Push tag
git push origin vX.Y.Z
```

#### 4. Open PR from `development` to `staging`

- **PR title**: `Release vX.Y.Z: <short title>`
- **PR body**: Content of the CHANGELOG entry for this version

#### 5. Create Release Entry on GitHub/Gitea

After the merge to `staging`, a release entry is created from the tag:

- **Title**: `vX.Y.Z — <short title>`
- **Body**: Content from the CHANGELOG for this version
- For MAJOR: migration guide as a separate section

---

### On PR to `main` (required)

No new tag — the version was already set during the staging release. The merge to `main` confirms the same state as the production release.

- [ ] Customer sign-off on staging server is in place
- [ ] All integration tests are green
- [ ] PR reviewed and approved (lead developer)
- [ ] After merge: wait for automatic production deployment
- [ ] Carry out post-deployment verification (service status, logs, availability)
- [ ] Ensure `staging` and `development` are in sync with `main` (merge `main` back if necessary)

---

## Pre-Release Checks (before every staging PR)

- [ ] Version number bumped (SemVer)
- [ ] CHANGELOG updated and committed
- [ ] Git tag set and pushed
- [ ] CI checks on `development` are green
- [ ] PR reviewed and approved by team member

---

## Rules & Conventions

- **No force-pushing to `main`, `staging`, or tags.**
- Tags are immutable — a tag that has been set is never moved or deleted.
- PATCH releases do not require a detailed release entry; a tag with a short description is sufficient.
- MAJOR releases always require a migration guide in the CHANGELOG and in the release entry.
- The version number is always set on `development`, never directly on `staging` or `main`.

---

## Version History (Example)

| Version | Date | Type | Description |
|---|---|---|---|
| `v1.0.0` | 2025-01-15 | MAJOR | Initial stable release |
| `v1.1.0` | 2025-03-10 | MINOR | Raven and DATEV export added |
| `v1.1.1` | 2025-03-22 | PATCH | Fix: SSH key path in deploy.sh |

---

*Last updated: May 2026*
