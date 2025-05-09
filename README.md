
# ERPNext Infrastructure Repository

Dieses Repository enthält Skripte und Konfigurationen zur Verwaltung und Bereitstellung von ERPNext-Instanzen in verschiedenen Szenarien. Es ist in mehrere Verzeichnisse unterteilt, die jeweils spezifische Funktionen und Anwendungsfälle abdecken.

---

## 📁 Directory Overview

### 1. `dev_container_scenario`

Dieses Verzeichnis enthält Skripte und Konfigurationen für die Entwicklung und das Testen von ERPNext in einer Devcontainer-Umgebung. Es dient dem Aufbau einer lokalen Entwicklungsumgebung mit Docker und Visual Studio Code.

#### Enthaltene Dateien:

- `frappe_docker-cleanrepository.sh` – Bereinigt die Devcontainer-Umgebung.
- `frappe_docker-prepare-devcontainer.sh` – Bereitet die Devcontainer-Umgebung vor (Volumes, Konfigurationen).
- `frappe_docker-reinstall.sh` – Installiert ERPNext im Devcontainer neu.
- `frappe_docker-installApp.sh` – Installiert zusätzliche Apps im Devcontainer.

---

### 2. `erpnext_container_scenario`

Dieses Verzeichnis enthält Skripte und Konfigurationen zur Bereitstellung von ERPNext in einer containerisierten Umgebung. Die Verwaltung erfolgt über das Tool `scenario.deploy`.

#### Voraussetzungen

```bash
git clone git@github.com:Cerulean-Circle-GmbH/MIMS.git
export PATH=$PATH:/path/to/MIMS
```

#### Verwendung von `scenario.deploy`

```bash
Usage: scenario.deploy <scenario> [init,up,stop,start,down,deinit,test,logs,updateconfig] [-v|-s|-h]

Lifecycle Actions:
  init        - Initialisiert das Szenarioverzeichnis
  up          - Erstellt und startet das Szenario
  stop        - Stoppt das Szenario
  start       - Startet das Szenario erneut
  down        - Stoppt und entfernt das Szenario
  deinit      - Entfernt das Verzeichnis (Konfiguration bleibt erhalten)

Service Actions:
  test        - Testet das laufende Szenario
  logs        - Sammelt Logs des Szenarios
  updateconfig - Aktualisiert die lokale Konfiguration

Optionen:
  -v, --verbose  - Detaillierte Ausgabe
  -s, --silent   - Stille Ausführung
  -h, --help     - Hilfe anzeigen
```

#### Beispiel-Befehle

```bash
scenario.deploy dev init
scenario.deploy dev up
scenario.deploy dev stop
scenario.deploy dev start
scenario.deploy dev deinit
```

#### Verfügbare Szenarien

- `com/schmidtundtoechter/test/erpnext-demo`
- `com/schmidtundtoechter/test/erpnext`
- `com/schmidtundtoechter/test/traefik`
- `de/matthiaskittner/automate/erpnext-demo`
- `de/matthiaskittner/automate/erpnext-swissnorm`
- `de/matthiaskittner/automate/erpnext`

---

### 3. `ssh_container_service`

Dieses Verzeichnis enthält Skripte und Konfigurationen zur Verwaltung von SSH-Diensten in einer containerisierten Umgebung. Es dient der Aktivierung und Verwaltung von SSH-Zugängen zu Containern.

#### Enthaltene Dateien:

- `Dockerfile` – Basis-Image für SSH-Dienste.
- `setup.sh` – Setup-Skript für SSH-Dienste.
- `config` – Beispielkonfigurationen für SSH.

---

## 🛠️ Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Git](https://git-scm.com/downloads)
- [Visual Studio Code](https://code.visualstudio.com/download)

---

## 🚀 Quick Start

### Devcontainer Setup

1. Cleanup:
   ```bash
   ./dev_container_scenario/frappe_docker-cleanrepository.sh
   ```
2. Prepare:
   ```bash
   ./dev_container_scenario/frappe_docker-prepare-devcontainer.sh
   ```
3. Reinstall:
   ```bash
   ./dev_container_scenario/frappe_docker-reinstall.sh
   ```

### Scenario Setup

1. Wechsle ins Verzeichnis:
   ```bash
   cd erpnext_container_scenario
   ```

2. Starte ein Szenario:
   ```bash
   scenario.deploy <scenario> up
   ```

---

## 📝 Notes

- Stelle sicher, dass das `MIMS`-Repository korrekt geklont ist und sich im `PATH` befindet.
- Verwende `scenario.deploy` ausschließlich im Verzeichnis `erpnext_container_scenario`.

---

> Dieses Repository richtet sich an Entwickler und Administratoren, die ERPNext flexibel und strukturiert betreiben wollen.
