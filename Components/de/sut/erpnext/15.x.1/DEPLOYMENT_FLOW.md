# Deployment Flow — ERPNext / Frappe (15.x.1)

Dieses Dokument beschreibt, was bei jedem MIMS-Step passiert, wann Apps installiert/deinstalliert werden und wie frappe/erpnext versioniert sind.

---

## Architektur-Überblick

```
scenario.deploy <scenario> <steps>     ← MIMS-Wrapper (lokal)
    └── scenario.sh <step>             ← Läuft auf dem Remote-Server
          └── docker compose up        ← Startet Container
                └── create-site        ← Führt install_upgrade_apps.sh aus
```

Alle Daten-Volumes sind **external** (persistent über down/up hinaus):

| Volume            | Inhalt                            |
|-------------------|-----------------------------------|
| `apps`            | Frappe-App-Quellcode (git-Repos)  |
| `sites`           | Site-Config, DB-Dumps, Backups    |
| `env`             | Python-Virtualenv                 |
| `db-data`         | MariaDB-Daten                     |
| `redis-*`         | Redis-Persistenz                  |
| `logs`            | Bench-Logs                        |
| `assets`          | Statische Frontend-Assets         |

---

## Steps im Detail

### `update`

> **Rein informativ. Kein Deployment, keine Container-Änderung.**

```
scenario.deploy → scenario.sh update
```

1. Liest `apps.json` (oder konvertiert Legacy-Format)
2. Ruft für jede App `git ls-remote --tags` auf dem Remote-Repo auf
3. Schreibt `apps.updated.json` mit Vorschlägen für neuere Tags (gleiche Major-Version)
4. Gibt für `FRAPPE_VERSION` / `ERPNEXT_VERSION` aus `.env` ebenfalls Vorschläge aus
5. **Ändert nichts** — weder Dateien noch Container

→ Zum Übernehmen: `apps.updated.json` prüfen und manuell in `apps.json` / `.env` eintragen.

---

### `down`

```
scenario.deploy → scenario.sh down → deploy-tools.down → docker compose down
```

1. Prüft Data-Volumes (mit `nocreate` — legt keine neuen an)
2. Stoppt alle Container und entfernt sie
3. **Alle Volumes bleiben erhalten** (extern deklariert in docker-compose.yml)

→ Daten (DB, Apps, Sites, Redis) sind nach `down` vollständig vorhanden, nur Container-Prozesse weg.

---

### `init`

> **Nur MIMS-intern. Kein `init` in `scenario.sh` implementiert.**

```
scenario.deploy init
```

1. Führt `config` aus (liest/fragt Szenario-Konfiguration)
2. Kopiert Komponenten-Dateien + Szenario-spezifische Dateien in ein lokales Temp-Verzeichnis
3. Schreibt expandierte `.env`-Datei (alle `SCENARIO_*`-Variablen aufgelöst)
4. **rsync** → überträgt alles auf den Remote-Server in `$SCENARIO_SERVER_CONFIGSDIR/<namespace>/<name>/`

**Kritisch**: `init` muss vor `up` ausgeführt werden, wenn `install_upgrade_apps.sh`, `apps.json` oder andere Dateien geändert wurden — sonst laufen die alten Versionen auf dem Server.

Übertragene Dateien u.a.:
- `scenario.sh`
- `docker-compose.yml`, `docker-compose.ports.yml`, `docker-compose.traefik.yml`
- `install_upgrade_apps.sh`  ← App-Installations-Logik
- `apps.json`                ← App-Liste mit `active: true/false`
- `fix-git-refs.sh`
- `direct_wildcard_fix.sh`
- `.env` (mit expandierten Variablen)

---

### `up`

```
scenario.deploy → scenario.sh up
    → checkAndCreateDataVolume  (legt Volumes an, falls nicht vorhanden)
    → docker compose build      (baut Docker-Image)
    → docker compose up -d      (startet alle Container)
```

**`docker compose build`** baut das ERPNext-Image mit:
- `FRAPPE_VERSION` aus `.env` → frappe-Basis-Image
- `ERPNEXT_VERSION` aus `.env` → erpnext wird im Image eingebaut

> frappe und erpnext sind **im Docker-Image eingebaut** (nicht in den Apps-Volumes). Sie werden NICHT via `install_upgrade_apps.sh` geupdated.

**`create-site` Container** (startet einmalig, `restart_policy: none`):

```
1. Wartet auf db:3306, redis-cache:6379, redis-queue:6379
2. Wartet auf sites/common_site_config.json mit db_host + redis_* Einträgen
3. bench new-site → legt Site an (nur wenn sites/<SITE_NAME>/site_config.json fehlt)
4. install_upgrade_apps.sh <SITE_NAME> <SCENARIO_INSTALL_APPS>
5. direct_wildcard_fix.sh   → Wildcard-Domain-Patch
6. docker restart backend + frontend Container
```

---

## `install_upgrade_apps.sh` — App-Verwaltung

Wird **bei jedem `up`** ausgeführt (auch wenn Site schon existiert).

### Ablauf

```
1. JSON lesen: apps.json (oder Legacy-Inline-Format konvertieren)
2. apps_installed = [frappe, erpnext]  ← immer behalten
3. Für jede App in apps.json:
   - active: true  → install_upgrade_app()
   - active: false → remove_app()
4. Alle app-Verzeichnisse unter apps/*:
   - nicht in apps_installed → remove_app()
5. bench update --requirements
6. bench --site <site> migrate
7. bench set-config developer_mode / server_script_enabled
8. bench clear-cache / clear-website-cache
```

### `install_upgrade_app()` — Installieren / Updaten

```bash
1. bench get-app <app> <repo> --branch <version>  # nur wenn apps/<app> fehlt
2. fix-git-refs.sh apps/<app>                      # konfiguriert git-Remotes
3. pushd apps/<app>
4. upstream-Remote sicherstellen (add falls fehlt)  # ← Fix: bench get-app klont als 'origin'
5. git fetch upstream <version>                     # Fehler → exit 1
6. git checkout <version>                           # Fehler → exit 1
7. git reset --hard upstream/<version>             # ← Fix: echtes Update der Working Copy
   (nur für Branch-Refs; Tags/Hashes brauchen das nicht)
8. bench install-app <app>  (wenn noch nicht installiert; retry mit --force)
```

**Versionstypen in apps.json:**

| Typ            | Beispiel           | Verhalten                                      |
|----------------|--------------------|------------------------------------------------|
| Branch         | `version-15`       | `git reset --hard upstream/version-15` → immer auf aktuellem Tip |
| Tag            | `v15.42.3`         | `git checkout v15.42.3` → exakt gepinnt        |
| Commit-Hash    | `abc1234`          | `git checkout abc1234` → exakt gepinnt         |

### `remove_app()` — Deinstallieren

```bash
1. bench list-apps | grep "^<app>"  → prüfen ob auf Site installiert
   (grep -q "^$app" statt -qx, da list-apps "appname version branch" ausgibt)
2. Wenn installiert:
   a. bench uninstall-app -y <app>
      (Fehler → remove-from-installed-apps als Fallback)
   b. bench remove-app <app>
      (Fehler nicht-fatal → manuelles Cleanup)
   c. grep -v aus sites/apps.txt
   d. rm -rf apps/<app>  +  archived/apps/<app>-*
3. Wenn nicht installiert → Debug-Log + bench list-apps ausgeben
```

---

## frappe / erpnext — Wie werden sie geupdated?

| Was            | Wo konfiguriert          | Wie geupdated                                  |
|----------------|--------------------------|------------------------------------------------|
| frappe         | `FRAPPE_VERSION` in `.env` | Neues Docker-Image bauen: `scenario.deploy <s> init,down,up` |
| erpnext        | `ERPNEXT_VERSION` in `.env` | Neues Docker-Image bauen: `scenario.deploy <s> init,down,up` |
| Zusatz-Apps    | `apps.json` → `version`  | `install_upgrade_apps.sh` bei jedem `up`       |

**Wichtig**: `update` (scenario.sh) ändert nur `apps.updated.json` — es deployed nichts. Die `.env`-Versionen für frappe/erpnext müssen manuell angepasst werden und dann braucht es ein vollständiges `init,down,up`.

---

## Typische Szenarien

### App hinzufügen
1. Eintrag in `apps.json` mit `"active": true`
2. `scenario.deploy <s> init,down,up`

### App deinstallieren
1. `apps.json`: `"active": false`
2. `scenario.deploy <s> init,down,up`

### App auf neue Version updaten (Tag/Branch)
1. `apps.json`: `"version": "v15.43.0"` oder neuer Branch
2. `scenario.deploy <s> init,down,up`

### frappe/erpnext updaten
1. `.env`: `FRAPPE_VERSION=version-15` / `ERPNEXT_VERSION=version-15`
2. `scenario.deploy <s> init,down,up`
   → `docker compose build` baut das Image neu

### Versionsstände prüfen (ohne Deployment)
```bash
scenario.deploy <s> update
```
→ gibt Vorschläge aus, kein Deployment

---

## Bekannte TODOs / Einschränkungen

- frappe und erpnext haben kein `.git`-Verzeichnis im Image → `bench update` für diese schlägt fehl (wird in `--requirements`-Modus umgangen)
- `bench build` (Assets neu bauen) ist auskommentiert — bei CSS/JS-Änderungen muss manuell gebaut werden
- `bench setup requirements --dev` läuft auf allen Instanzen (inkl. Produktion), da `developer_mode=1` global gesetzt ist
- Python-Venv muss bei Python-Version-Wechsel manuell neu gebaut werden
