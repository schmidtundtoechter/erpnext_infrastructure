# vars — Jenkins Shared Library

This directory is a [Jenkins Shared Library](https://www.jenkins.io/doc/book/pipeline/shared-libraries/)
that holds all common pipeline helper functions for the `kittner.netcup` repository.

## Purpose

Instead of copy-pasting the same SSH-setup, backup, update and cleanup logic across
every Jenkinsfile (which caused bugs to be fixed in 11 places), all shared functions
now live in **one file**: `vars/mkt.groovy`.

Each Jenkinsfile keeps only a small block of one-liner delegate wrappers at the top
(≈10 lines), making future fixes trivially applied in one place.

---

## One-time Jenkins setup (admin required)

Go to **Manage Jenkins → System → Global Pipeline Libraries** and add:

| Field | Value |
|---|---|
| **Name** | `mkt-lib` |
| **Default version** | `main` |
| **Retrieval method** | Modern SCM → Git |
| **Project Repository** | `https://github.com/mkt1/kittner.netcup.git` |
| **Library Path** (Advanced) | `vars` |

Enable **Allow default version to be overridden** and **Include @Library changes in job recent changes** as desired.

> After saving, Jenkins will automatically fetch `vars/mkt.groovy` from this
> repo whenever any pipeline with `@Library('mkt-lib@main') _` is triggered.

---

## File layout

```
vars/
  vars/
    mkt.groovy      ← all shared functions (the only file you need to edit for fixes)
  README.md         ← this file
```

---

## Available functions in `mkt.groovy`

### SSH setup

| Function | Used by |
|---|---|
| `mkt.setupSSHConfig()` | Single-host pipelines (ki, adlx, automate, sut, …) |
| `mkt.setupSSHConfigMultiHost()` | Reset-stage pipelines that copy data between two hosts |
| `mkt.setupSSHConfigAllHosts()` | Multi-host pipelines (matrix, services) |

All three write `${WORKSPACE}/.ssh_config` and create `ssh`/`scp` wrapper scripts
that force `-F`. Because those wrappers are placed in `${WORKSPACE}` (which is
prepended to `PATH` in each pipeline's `environment {}` block), every SSH/SCP call
automatically uses the job-local config — eliminating the old race condition.

### Backup

| Function | Description |
|---|---|
| `mkt.testConnection(serviceName)` | Health-check via `scenario.deploy … test -h` + SSH echo |
| `mkt.backupService(serviceName)` | Run `scenario.deploy … backup -v` |
| `mkt.cleanupOldBackups(extraCmd='')` | Copy `cleanupOldArchives.sh` to host and run it; optional second pass via `extraCmd` |
| `mkt.cleanupDockerImages()` | Copy `cleanupDockerImages.sh` to host and run it |

### Update

| Function | Description |
|---|---|
| `mkt.updateService(serviceName)` | Update with 2-attempt retry + recovery `up` on failure |
| `mkt.collectLogs(serviceName)` | Collect docker ps/logs/events/disk for diagnosis |

### Reset stage

| Function | Description |
|---|---|
| `mkt.resetStageScenario(serviceName, targetName)` | Sync backup from SOURCE_HOST, relink, restore |
| `mkt.serviceAction(action)` | Generic action on `SERVICE_NAME` env var (down/restore/up) |

### Checkout helpers

| Function | Description |
|---|---|
| `mkt.checkoutDependencies(checkoutErpnext=false, branch='main')` | Checkout MIMS; optionally also `erpnext_infrastructure` |
| `mkt.linkSutComponents(includeCom=false)` | Symlink `Components/de/sut`; optionally also `Scenarios/com` |

---

## How each Jenkinsfile uses the library

```groovy
@Library('mkt-lib@main') _

// Thin delegates — route calls from stage bodies to the shared library.
// Tip: for files that only need a subset, the unused delegates are harmless no-ops.
def setupSSHConfig()             { mkt.setupSSHConfig() }
def testConnection(String s)     { mkt.testConnection(s) }
def backupService(String s)      { mkt.backupService(s) }
// … etc.

pipeline {
    agent any
    environment { … }
    stages {
        stage('Test ki.netcup') {
            steps { script { testConnection('traefik') } }
        }
        // stage bodies are unchanged — they still call the short function names
    }
    post { … }
}
```

The delegate layer means: **stage bodies never change** when the library is updated.

---

## Making a fix

1. Edit `vars/mkt.groovy`
2. Commit + push to `main`
3. All pipelines pick up the fix on the next run automatically (no Jenkinsfile edits needed)
