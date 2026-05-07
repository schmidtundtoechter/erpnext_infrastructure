# Deployment Flow — ERPNext / Frappe (15.x.1)

Dieses Dokument beschreibt, was bei jedem MIMS-Step passiert, wann Apps installiert/deinstalliert/aktualisiert werden und wie frappe/erpnext versioniert sind.

**Designprinzip:** `down,up` aktualisiert nie. Es startet Container neu und gleicht den App-Installationsstatus an `apps.json` an. Ein echtes Update wird ausschließlich über den `update`-Step vorbereitet und ausgelöst.

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

## Typische Abläufe

### Normaler Neustart (kein Update)

```bash
scenario.deploy <scenario> down,up
```

- Container stoppen und neu starten.
- Kein Docker-Pull, kein `build --pull`.
- Keine App-Upgrades, keine Migrationen.
- `install_upgrade_apps.sh` läuft im **reconcile**-Modus: fehlende Apps werden installiert, deaktivierte entfernt, vorhandene aktive Apps bleiben unverändert.

### Update vorbereiten und ausführen

```bash
# Schritt 1: Versionsvorschläge erzeugen, Images aktualisieren, Upgrade-Marker setzen
scenario.deploy <scenario> init,update

# Schritt 2: apps.updated.json und .env-Vorschläge prüfen und manuell übernehmen
# Dann: Dateien hochladen und Upgrade ausführen
scenario.deploy <scenario> init,update,down,up
```

`init,update` allein erzeugt den Upgrade-Marker `sites/.run-app-upgrade`. Bleibt er liegen (kein `up` danach), wird der Upgrade beim nächsten `up` nachgeholt — das ist gewollt.

---

## Steps im Detail

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

### `update`

> **Update-Vorbereitung: Versionsvorschläge, Docker-Pull/Build, Upgrade-Marker.**

```
scenario.deploy → scenario.sh update
```

1. Liest `apps.json` (oder konvertiert Legacy-Format)
2. Ruft für jede App `git ls-remote --tags` auf dem Remote-Repo auf
3. Schreibt `apps.updated.json` mit Vorschlägen für neuere Tags (gleiche Major-Version)
4. Gibt für `FRAPPE_VERSION` / `ERPNEXT_VERSION` aus `.env` Versions-Vorschläge aus
5. Führt `docker compose pull` aus (nur Registry-Images; build-only Images werden übersprungen)
6. Führt `docker compose build --pull` aus
7. Schreibt `sites/.run-app-upgrade` über einen kurzlebigen Compose-Container in das persistente Sites-Volume

`update` ist der **einzige Step**, der Images explizit aktualisiert. Bleibt danach kein `down,up` aus, liegt die Marker-Datei einfach liegen und wird beim nächsten `up` aufgegriffen.

---

### `down`

```
scenario.deploy → scenario.sh down → deploy-tools.down → docker compose down
```

1. Prüft Data-Volumes (mit `nocreate` — legt keine neuen an)
2. Stoppt alle Container und entfernt sie
3. **Alle Volumes bleiben erhalten** (extern deklariert in docker-compose.yml)

Daten (DB, Apps, Sites, Redis) sind nach `down` vollständig vorhanden — nur Container-Prozesse weg.

---

### `up`

```
scenario.deploy → scenario.sh up
    → checkAndCreateDataVolume  (legt Volumes an, falls nicht vorhanden)
    → docker compose up -d      (startet alle Container)
```

`up` führt kein explizites `pull` und kein `build --pull` aus. Es verwendet schlicht `docker compose up -d`. Fehlt das lokale Image, darf Docker Compose es bauen; existiert es bereits, wird es nicht aktualisiert.

**Das ERPNext-Image** wird mit folgenden Build-Args gebaut:
- `FRAPPE_VERSION` aus `.env` → frappe-Basisimage
- `ERPNEXT_VERSION` aus `.env` → ERPNext wird im Image eingebaut

> `frappe` und `erpnext` sind **im Docker-Image eingebaut** (nicht in den Apps-Volumes). Sie werden nicht via `install_upgrade_apps.sh` aktualisiert. Für reproduzierbare Stände sind Tags in `.env` besser als bewegliche Branch-Namen.

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

Wird **bei jedem `up`** ausgeführt (auch wenn die Site bereits existiert). Der Modus hängt von der Marker-Datei `sites/.run-app-upgrade` ab:

| Marker-Datei vorhanden | Modus       |
|------------------------|-------------|
| Nein                   | `reconcile` |
| Ja                     | `upgrade`   |

### Ablauf

```
1. apps.json lesen (oder Legacy-Inline-Format konvertieren)
2. Modus bestimmen (Marker-Datei sites/.run-app-upgrade)
3. apps_installed = [frappe, erpnext]  ← immer behalten
4. Für jede App in apps.json:
   - active: true  → reconcile_app() oder upgrade_app()
   - active: false → remove_app()
5. Alle App-Verzeichnisse unter apps/* die nicht in apps_installed sind → remove_app()
6. Im reconcile-Modus:
   - keine Git-Updates, keine Requirements, keine pauschale Migration
   - Migration/Cache-Clear nur bei Statusänderung (Neuinstallation)
7. Im upgrade-Modus:
   - Requirements aktualisieren
   - Site migrieren
   - Cache leeren
   - Marker-Datei nach Erfolg löschen
   - Schlägt der Upgrade fehl, bleibt die Marker-Datei erhalten → nächster up wiederholt ihn
```

### Modus `reconcile` — Installationsstatus abgleichen

Default bei jedem normalen `up`.

```bash
1. Wenn apps/<app> fehlt:          bench get-app <app> <repo> --branch <version>
2. Wenn App auf der Site fehlt:    bench install-app <app>
3. Wenn App bereits installiert:   nichts tun
```

Nicht ausgeführt im reconcile-Modus:
`git fetch` · `git checkout` · `git reset --hard` · `bench update --requirements` · `pip install --upgrade` · `bench migrate` (pauschal) · `bench setup requirements --dev`

### Modus `upgrade` — Installieren / Updaten

Läuft nur, wenn `sites/.run-app-upgrade` existiert.

```bash
1. bench get-app <app> <repo> --branch <version>   # nur wenn apps/<app> fehlt
2. fix-git-refs.sh apps/<app>                       # konfiguriert git-Remotes
3. app_remote dynamisch lesen (git remote | head -n 1)
4. Wenn Remote vorhanden:
   git fetch <app_remote> <version>
   git checkout <version>
   Bei Branch-Refs: git reset --hard <app_remote>/<version>
5. Wenn kein Remote vorhanden: Remote-Teil überspringen (kein Abbruch)
6. bench install-app <app>  (wenn noch nicht installiert; retry mit --force)
7. Requirements aktualisieren, Site migrieren, Cache leeren
8. Marker-Datei löschen
```

**Versionstypen in apps.json:**

| Typ         | Beispiel      | Verhalten                                                      |
|-------------|---------------|----------------------------------------------------------------|
| Branch      | `version-15`  | `git reset --hard <remote>/version-15` (wenn Remote vorhanden)|
| Tag         | `v15.42.3`    | `git checkout v15.42.3` → exakt gepinnt                       |
| Commit-Hash | `abc1234`     | `git checkout abc1234` → exakt gepinnt                        |

### `remove_app()` — Deinstallieren

```bash
1. bench list-apps | grep "^<app>"  → prüfen ob auf Site installiert
   (grep -q "^$app" statt -qx, da list-apps "appname version branch" ausgibt)
2. Wenn installiert:
   a. bench uninstall-app -y <app>
      (Fehler → remove-from-installed-apps als Fallback)
   b. bench remove-app <app>
      (Fehler nicht-fatal → manuelles Cleanup nötig)
   c. grep -v aus sites/apps.txt
   d. rm -rf apps/<app>  +  archived/apps/<app>-*
3. Wenn nicht installiert → Debug-Log + bench list-apps ausgeben
```

---

## frappe / erpnext — Wie werden sie geupdated?

| Was            | Wo konfiguriert          | Wie geupdated                                  |
|----------------|--------------------------|------------------------------------------------|
| frappe         | `FRAPPE_VERSION` in `.env` | Neues Docker-Image bauen: `scenario.deploy <s> init,update,down,up` |
| erpnext        | `ERPNEXT_VERSION` in `.env` | Neues Docker-Image bauen: `scenario.deploy <s> init,update,down,up` |
| Zusatz-Apps    | `apps.json` → `version`  | Upgrade-Modus über `sites/.run-app-upgrade` beim folgenden `up` |

**Wichtig**: `update` (scenario.sh) erzeugt weiterhin Vorschläge, macht aber zusätzlich Pull/Build und setzt den Upgrade-Marker. Die `.env`-Versionen für frappe/erpnext müssen vorher per `init` auf den Server übertragen werden.

Zusatz: Ein normales `down,up` triggert keinen Pull und keinen `build --pull`. Für harte Reproduzierbarkeit sollten trotzdem Tags oder Commit-Hashes statt beweglicher Branch-Namen verwendet werden.

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
2. `scenario.deploy <s> init,update,down,up`

### frappe/erpnext updaten
1. `.env`: `FRAPPE_VERSION=version-15` / `ERPNEXT_VERSION=version-15`
2. `scenario.deploy <s> init,update,down,up`
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
