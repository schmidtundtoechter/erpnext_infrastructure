
# ERPNext Infrastructure Repository

This repository contains scripts and configurations for managing and deploying ERPNext instances in various scenarios. It is divided into multiple directories, each covering specific functions and use cases.

---

## 📁 Directory Overview

### 1. `erpnext_container_scenario`

This directory contains scripts and configurations for deploying ERPNext in a containerized environment. Management is done using the `scenario.deploy` tool.

#### Prerequisites

```bash
git clone git@github.com:Cerulean-Circle-GmbH/MIMS.git
export PATH=$PATH:/path/to/MIMS
```

#### Using `scenario.deploy`

```bash
Usage: scenario.deploy <scenario> [init,up,stop,start,down,deinit,test,logs,updateconfig,backup,restore,update] [-v|-s|-h]

Lifecycle Actions:
    init        - Init remote scenario dir
    up          - Create and start scenario
    stop        - Stop scenario
    start       - Start scenario if stopped
    down        - Stop and shut down scenario
    deinit      - Cleanup/remove remote and local scenario dir (leave config untouched)

Service Actions:
    test        - Test the running scenario
    logs        - Collect logs of scenario
    updateconfig - Update local scenario config

Deployment Actions:
    backup      - Backup scenario
    restore     - Restore scenario from backup
    update      - Update scenario services

Options:
    -v, --verbose  - Verbose output
    -s, --silent   - Silent execution
    -h, --help     - Show help

Note: 
- deinit will call down automatically
```

#### Example Commands

```bash
# Initialize a scenario
scenario.deploy dev init

# Start scenario (includes init + stop if needed)
scenario.deploy dev up

# Stop running scenario
scenario.deploy dev stop

# Start stopped scenario
scenario.deploy dev start

# Shutdown and remove scenario
scenario.deploy dev down

# Complete cleanup
scenario.deploy dev deinit

# Combined operations
scenario.deploy dev stop,start
scenario.deploy dev deinit,init
scenario.deploy dev down,up
```

#### Available Scenarios

- `com/schmidtundtoechter/test/erpnext-demo`
- `com/schmidtundtoechter/test/erpnext-effekt-etage`
- `com/schmidtundtoechter/test/erpnext-m`
- `com/schmidtundtoechter/test/erpnext-test`
- `com/schmidtundtoechter/test/erpnext-ueag`
- `com/schmidtundtoechter/test/gitea`
- `com/schmidtundtoechter/test/traefik`

#### Action Details & Use Cases

##### 1. `deinit,init` - Complete Reset
**What happens:**
- `deinit`: Calls `down` automatically → stops containers, removes networks, cleans up local/remote directories
- `init`: Creates fresh scenario directory structure, prepares configuration files

**Use case:** Complete environment reset, useful when switching between different configurations or after major changes.

##### 2. `stop,start` - Service Restart
**What happens:**
- `stop`: Gracefully stops all running containers (preserves data volumes and networks)
- `start`: Restarts the stopped containers with existing configuration

**Use case:** Quick restart for configuration changes that don't require rebuilding, maintenance windows, or troubleshooting.

##### 3. `down,up` - Full Recreation
**What happens:**
- `down`: Stops and removes containers, networks, and non-persistent volumes
- `up`: Creates and starts fresh containers

**Use case:** Major updates, Docker image changes, or when you need to ensure clean state without affecting persistent data.

##### 4. `test` - Health Check
**What happens:**
- Runs automated tests against the running scenario
- Checks container health, network connectivity, and service availability
- Validates that all expected services are responding correctly

**Use case:** Verify deployment success, continuous monitoring, or before promoting to production.

##### 5. `update` - Service Updates
**What happens:**
- Pulls latest Docker images
- Applies configuration updates
- Performs rolling updates where possible
- Maintains data persistence during updates

**Use case:** Apply security patches, feature updates, or configuration changes without data loss.

##### 6. `logs` - Log Collection
**What happens:**
- Collects logs from all containers in the scenario
- Aggregates and formats log output for analysis
- May include both application and system logs

**Use case:** Debugging issues, monitoring application behavior, or compliance logging.

##### 7. `updateconfig` - Configuration Sync
**What happens:**
- Synchronizes local configuration with remote scenario configuration
- Updates environment variables and configuration files
- Prepares local environment for deployment

**Use case:** Keep local development environment in sync with remote configurations, apply new settings.

##### 8. `backup` - Data Backup
**What happens:**
- Creates compressed backups of all persistent data volumes
- Generates timestamped backup files (e.g., `scenario_20250804_120000_data.tar.gz`)
- Stores backups in designated backup directory
- Preserves database dumps, uploaded files, and configuration data

**Use case:** Before major updates, scheduled backups, disaster recovery preparation, or before risky operations.

##### 9. `restore` - Data Restoration
**What happens:**
- Restores data volumes from previously created backup files
- Cleans existing data volumes before restoration to ensure clean state
- Extracts backup archives into appropriate volume locations
- Maintains file permissions and ownership

**Use case:** Disaster recovery, rollback after failed updates, migrating data between environments, or restoring specific point-in-time states.

---

### 2. `ssh_container_service`

This directory contains scripts and configurations for managing SSH services in a containerized environment. It is used to enable and manage SSH access to containers.

#### Included Files:

- `Dockerfile` – Base image for SSH services.
- `setup.sh` – Setup script for SSH services.
- `config` – Example configurations for SSH.

---

## 🛠️ Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Git](https://git-scm.com/downloads)
- [Visual Studio Code](https://code.visualstudio.com/download)

---

## 🚀 Quick Start

### Scenario Setup

1. Navigate to the directory:
     ```bash
     cd erpnext_container_scenario
     ```

2. Start a scenario:
     ```bash
     scenario.deploy <scenario> init,up -v
     ```

---

## 📝 Notes

- Ensure that the `MIMS` repository is correctly cloned and included in the `PATH`.
- Use `scenario.deploy` exclusively in the `erpnext_container_scenario` directory.

---

> This repository is aimed at developers and administrators who want to operate ERPNext flexibly and in a structured manner.

