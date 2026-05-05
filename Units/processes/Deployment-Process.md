# Deployment Process

Branch-based deployment process with 4 stages.

---

## Branching Model

```
main
 └── staging
      └── development
            └── feature/<name>
            └── fix/<name>
```

- **`main`** is the production-ready state. Every merge to `main` triggers an automatic deployment to the production system.
- **`staging`** is the customer acceptance branch. A merge to `staging` triggers an automatic deployment to the customer's staging server. Before deployment, the staging server is brought up to the current state of the production system (data copy from production).
- **`development`** is the team development branch. Feature and fix branches are forked from `development` and merged back via pull request. The `development` branch is hosted on **test.schmidtundtoechter.com** and can be tested there at any time.

---

## The 4 Stages

### Stage 1 — Local Development (Docker)

- Development takes place locally in a Docker environment.
- Every feature and fix gets its own branch.
- Branch naming convention: `feature/<short-name>` or `fix/<short-name>`.
- Commit messages follow the format: `<type>: <short description>` (e.g. `feat: add bench configuration`, `fix: correct SSH key path`).
- Local tests and syntax checks are run before the first push.

### Stage 2 — Test Server test.schmidtundtoechter.com (development)

- When a feature or fix is ready, a pull request from `feature/*` or `fix/*` to **`development`** is opened.
- A team member performs a **code review** and approves the PR.
- After the merge, `development` is updated on **test.schmidtundtoechter.com**.
- The team tests the changes there and ensures everything works correctly.
- Bugs are fixed as a new `fix/*` branch and merged back into `development` via PR.

### Stage 3 — Customer Staging Server (staging)

- When the development state is ready for customer acceptance, a new version is created **before opening the PR**: bump the version number, update the CHANGELOG, and set the Git tag on `development` (see [Release Process](Release-Process.md)).
- A pull request from **`development`** to **`staging`** is then opened — the PR title carries the new version number (`Release vX.Y.Z: ...`).
- **Before deployment** to `staging`, the staging server is fully synchronised with the data and state of the production system (production data is copied to the staging server). This ensures the customer tests under realistic conditions.
- `staging` is then automatically deployed to the customer's staging server.
- The customer reviews the changes on the staging server.
- At the same time, all **integration tests** must pass cleanly.
- Bugs found are created as a `fix/*` branch from `development`, tested via `development`, and brought to `staging` again via PR — no direct pushing to `staging`.

### Stage 4 — Production (main)

- When the customer has given their sign-off **and** all integration tests are green, a pull request from **`staging`** to **`main`** is opened.
- The PR is reviewed and approved by at least one lead developer.
- After the merge to `main`, an **automatic deployment** to the production system is triggered.
- After deployment: a brief verification check (service status, logs, availability).
- The release tag was already set during the staging PR — no new tag required (see [Release Process](Release-Process.md)).

---

## Overview: Who Deploys Where

| Branch        | Server                          | Trigger                        | Precondition                                       |
|:--------------|:--------------------------------|:-------------------------------|:---------------------------------------------------|
| `development` | test.schmidtundtoechter.com     | Manually after merge           | Code review by team member                        |
| `staging`     | Customer staging server         | Automatically after merge      | Staging server synchronised with production data  |
| `main`        | Production system               | Automatically after merge      | Customer sign-off + integration tests green       |

---

## Hotfix Process

Critical production bugs can be branched directly from `main`:

```
main
 └── hotfix/<name>
```

1. Create branch `hotfix/<name>` from `main`.
2. Develop and commit the fix.
3. Open PR to `main` (urgent, simplified review by lead developer).
4. After merge: automatic production deployment, set patch release tag.
5. Merge `main` back into `staging` and `development` to avoid divergence.

---

## Deployment Checklist

### PR to `development`
- [ ] Code review carried out and approved by team member
- [ ] Local tests green

### PR to `staging`
- [ ] Version number bumped, CHANGELOG updated, Git tag set on `development`
- [ ] development state tested on test.schmidtundtoechter.com
- [ ] Staging server synchronised with production data
- [ ] Deployment to staging server successful

### PR to `main`
- [ ] Customer sign-off on staging server granted
- [ ] All integration tests green
- [ ] PR reviewed and approved (lead developer)
- [ ] Post-deployment verification on production system completed
- [ ] Release tag set

---

*Last updated: May 2026*
