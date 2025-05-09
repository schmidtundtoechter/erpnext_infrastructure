
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
Usage: scenario.deploy <scenario> [init,up,stop,start,down,deinit,test,logs,updateconfig] [-v|-s|-h]

Lifecycle Actions:
    init        - Initializes the scenario directory
    up          - Creates and starts the scenario
    stop        - Stops the scenario
    start       - Restarts the scenario
    down        - Stops and removes the scenario
    deinit      - Removes the directory (configuration remains intact)

Service Actions:
    test        - Tests the running scenario
    logs        - Collects logs of the scenario
    updateconfig - Updates the local configuration

Options:
    -v, --verbose  - Detailed output
    -s, --silent   - Silent execution
    -h, --help     - Show help
```

#### Example Commands

```bash
scenario.deploy dev init
scenario.deploy dev up
scenario.deploy dev stop
scenario.deploy dev start
scenario.deploy dev deinit
```

#### Available Scenarios

- `com/schmidtundtoechter/test/erpnext-demo`
- `com/schmidtundtoechter/test/erpnext`
- `com/schmidtundtoechter/test/traefik`
- `de/matthiaskittner/automate/erpnext-demo`
- `de/matthiaskittner/automate/erpnext-swissnorm`
- `de/matthiaskittner/automate/erpnext`

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

