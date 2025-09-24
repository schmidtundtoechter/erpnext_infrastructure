# ERPNext Infrastructure — Übersicht (Deutsch)

Diese Datei gibt eine kompakte, deutschsprachige Übersicht über das gesamte Repository, dessen Struktur, Zweck und typische Bedienung. Sie ergänzt die vorhandene englische `README.md` mit konkreten Hinweisen für Entwickler und Betreiber.

## Kurzer Überblick

Dieses Repository enthält Skripte, Szenarios und Infrastruktur-Konfigurationen, um ERPNext in containerisierten Umgebungen zu betreiben, zu testen und zu verwalten. Es bündelt mehrere Szenario-Sammlungen, Komponenten (z. B. Container-Images / Dienstkonfigurationen) und Hilfswerkzeuge (z. B. SSH-Service-Container).

Zielgruppe: Entwickler, DevOps-Engineers und Administratoren, die ERPNext in Docker-/Container-Szenarien aufsetzen, testen oder in CI/CD einsetzen wollen.

## Hauptverzeichnisse (kurz)

- `erpnext_container_scenario/` — zentral für containerisierte ERPNext-Szenarios. Enthält scenario-Skripte, Szenario-Definitionen, Beispiel-Scenarios und Hilfs-Skripte.
- `MIMS/` — Sammlung von Komponenten, Tools und Hilfsskripten (externe Abhängigkeit; wird im Root-README erwähnt). Manche Utility- und Deploy-Skripte werden hier erwartet.
- `ssh_container_service/` — Dockerfile und Konfigurationen zum Bereitstellen eines SSH-Services in Containern.

Weitere Unterverzeichnisse:
- `Components/` — fertige Komponentenpakete (nach Organisations-/Länderkonventionen abgelegt).
- `Scenarios/` — definierte Szenarios (z. B. `com/schmidtundtoechter/test/...`).

## Wichtige Konzepte

- Szenario (scenario): Eine Sammlung von Compose-/Kubernetes- oder Container-Definitionsdateien und Hilfsskripten, die zusammen ein lauffähiges Test-/Dev-System aufbauen (z. B. ERPNext + Traefik + Datenbank).
- `scenario.deploy` / `scenario`-Werkzeuge: CLI-Skripte (aus `MIMS`), um Szenarios zu initialisieren, hochzufahren, runterzufahren, Logs zu sammeln und zu testen.
- Komponenten: Wiederverwendbare Container- oder Konfigurationspakete unter `Components/`.

## Detaillierte Ordnerbeschreibung

erpnext_container_scenario/
- `scenario.deploy` (nutzbar mit dem `MIMS`-Toolset) — steuert Lifecycles von Szenarios (init, up, stop, start, down, deinit, test, logs, updateconfig).
- `_scenarios/` und `Scenarios/` — tatsächliche Szenario-Definitionen, z. B. `com/schmidtundtoechter/test/`.
- Beispielskripte: `convert-backup.sh`, `scenario.update`, `scenario.reinstall` etc. — Hilfen für Betriebsaufgaben.

ssh_container_service/
- Bereitstellung eines schlanken SSH-Dienstes als Container. Enthält `Dockerfile`, `docker-compose.yml`, Start-/Stop-Skripte und SSH-Keys.

MIMS/
- Sammlung von Hilfs- und Deploy-Tools. Wird typischerweise als separates Repo geklont und dem `PATH` hinzugefügt (siehe Root-README). Viele Szenario-Operationen setzen die Verfügbarkeit von `MIMS` voraus.

## Quick Start (lokal)

1. Repository klonen / in das Verzeichnis wechseln.
2. MIMS verfügbar machen (falls noch nicht):

   - Clone: `git clone git@github.com:Cerulean-Circle-GmbH/MIMS.git`
   - PATH erweitern: `export PATH=$PATH:/pfad/zu/MIMS`

3. In ein Szenario-Verzeichnis wechseln:

   - Beispiel: `cd erpnext_container_scenario`

4. Szenario initialisieren und starten (Beispiel):

   - `scenario.deploy com/schmidtundtoechter/test/erpnext init`
   - `scenario.deploy com/schmidtundtoechter/test/erpnext up`

5. Logs / Tests / Stop:

   - Logs: `scenario.deploy <scenario> logs`
   - Stop: `scenario.deploy <scenario> stop`
   - Down (vollständig entfernen): `scenario.deploy <scenario> down`

Hinweis: Einige Szenarios erwarten zusätzliche Umgebungsdateien wie `*.scenario.env` (z. B. `Scenarios/com/schmidtundtoechter/test/gitea.scenario.env`). Achte auf fehlende Secrets/Schlüssel.

## Typische Namens- und Ablagekonventionen

- Szenarios werden nach Reverse-Domain-Notation abgelegt: `com/organisation/projekt/...`.
- Komponenten liegen strukturiert nach Land/Organisation in `Components/`.
- Deploy- und Managementskripte befinden sich in den jeweiligen Szenario-Ordnern.

## Wichtige Dateien

- `scenario.deploy` (im Root von `erpnext_container_scenario`) — CLI-Steuerung für Szenarios.
- `docker-compose.yml`, `Dockerfile` — Container-Definitionen.
- `*.scenario.env` — Umgebungs- und Secret-Overlays für Szenarios.

## Hinweise zur Entwicklung und zum Debugging

- Prüfe zuerst die Umgebungsdateien (`*.env`, `*.scenario.env`) auf fehlende Variablen.
- Nutze `scenario.deploy <scenario> logs` und `docker-compose logs` (im Szenario-Ordner), um Service-Logs zu prüfen.
- SSH in Container: `ssh_container_service` stellt Hilfs-Container bereit; alternative: `docker exec -it <container> /bin/bash`.

## Troubleshooting (häufige Probleme)

- MIMS nicht im PATH: `scenario.deploy` steht nicht zur Verfügung. Lösung: MIMS klonen und PATH setzen.
- Ports belegt: Prüfe lokale Dienste (z. B. Traefik / nginx / Datenbank) und passe Ports in `docker-compose.yml` an.
- Fehlende Secrets / Keys: Einige Szenarios erwarten vorhandene SSH-Keys oder API-Tokens.

## Contribution & Weiterentwicklung

- Vorschläge per Pull Request an diesem Repository.
- Bei größeren Änderungen an Szenarios: neue `Scenarios/<...>`-Struktur anlegen und Dokumentation ergänzen.

## Nächste Schritte / Empfehlungen

- README.md übersetzen/ergänzen, falls spezifische Komponenten detaillierter dokumentiert werden sollen.
- Tests/Sanity-Checks als CI-Job (z. B. `scenario.deploy <scenario> test`) hinzufügen.

---

Anhang: Anforderungen-Checkout

- Anforderung: "Dokumentation, die das gesamt repository, funktionsweise, layout etc. auf deutsch erklärt" — Status: Erledigt (neue Datei `README.de.md`).
