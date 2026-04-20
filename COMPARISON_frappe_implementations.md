# Vergleich: Frappe/ERPNext Implementierungen

| Aspekt | `kittner.netcup` (io/frappe/15.x) | `erpnext_infrastructure` (de/sut/erpnext/15.x) |
|---|---|---|
| **Architektur** | Monolithisch: frappe, worker, scheduler, db, redis, init (6 Container) | Microservices: backend, frontend, configurator, create-site, db, queue-long, queue-short, redis-cache, redis-queue, scheduler, websocket (11 Container) |
| **Dockerfile Basis** | `frappe/bench:latest` (einfach, schnell) | `python:3.11.6-slim-bookworm` (vollständig eigener Build, multi-stage) |
| **PDF-Erzeugung** | Nicht vorhanden | `wkhtmltopdf` + `weasyprint` Dependencies im Image |
| **Node.js** | Kommt von Basis-Image | NVM mit pinned Version (`v20.19.2`) |
| **Backup-Tool** | Nicht im Image | `restic` direkt im Image installiert |
| **Nginx** | Läuft innerhalb `bench start` im frappe-Container | Dedizierter `frontend`-Container mit eigenem `nginx-template.conf` |
| **Sicherheits-Header** | Keine expliziten Header | `X-Frame-Options`, `HSTS`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy` in nginx-config |
| **Traefik-Port** | 8000 | 8080 |
| **Volumes** | 3 (bench-data, db-data, redis-data) | 8 (env, apps, sites, logs, redis-queue-data, redis-cache-data, db-data, assets) |
| **DB Root Password** | `${DB_ROOT_PASSWORD}` (env var) | `admin` (hardcoded!) |
| **App-Management** | `install_apps.sh`: nur Install, mit Deinstallation nicht genutzter Apps | `install_upgrade_apps.sh`: Install + Upgrade + Migration + Cache-Clear + Developer-Mode |
| **DB Wildcard-Fix** | `direct_wildcard_fix.sh` (löst IP-Wechsel-Problem) | Nicht vorhanden |
| **Git-Refs-Fix** | `fix-git-refs.sh` (robustes Fetching aller Remote-Branches) | Nicht vorhanden |
| **Site-Name-Erkennung** | Liest `default_site` aus `common_site_config.json` wenn SCENARIO_TRAEFIK_URL sich ändert | Nicht vorhanden |
| **Docker Compose** | `docker compose` (aktuell) | `docker-compose` (veraltet, deprecated) |

---

## Frappe-Funktionalitäten: Betriebsstatus im Vergleich

> Legende: ✅ funktioniert korrekt · ⚠️ funktioniert mit Einschränkungen · ❌ nicht funktionsfähig

| Funktion | kittner.netcup | erpnext_infrastructure | Bewertung |
|---|---|---|---|
| **HTTP / Gunicorn** | ⚠️ `bench serve` (Dev-Server via Procfile) | ✅ Gunicorn direkt: `--threads=4 --workers=2 --worker-class=gthread --preload` | erpnext besser – Production-WSGI statt Dev-Server |
| **WebSocket / Realtime** | ❌ **Nicht gestartet** – Procfile enthält nur `web: bench serve`, kein socketio-Prozess | ✅ Dedizierter `websocket`-Container (`node socketio.js`) | Echtzeit-Notifications, Progress-Bars, Formular-Live-Updates funktionieren in kittner.netcup **nicht** |
| **Worker (Background Jobs)** | ⚠️ Ein Container, alle Queues gemeinsam (`default,short,long`) | ✅ Zwei getrennte Worker: `queue-long` (`long,default,short`), `queue-short` (`short,default`) | erpnext besser – long-Jobs (z. B. Reports, Exports) blockieren keine short-Jobs (z. B. E-Mail-Versand) |
| **Scheduler** | ✅ Dedizierter Container, wartet auf `INITED`-File + `common_site_config.json` vor Start | ✅ Dedizierter Container, wartet auf `common_site_config.json` mit db_host/redis_cache/redis_queue-Keys | Beide korrekt |
| **Redis Cache** | ⚠️ Eine Redis-Instanz für Cache + Queue + SocketIO | ✅ Dedizierter `redis-cache`-Container mit `allkeys-lru` Eviction-Policy | erpnext besser – LRU-Eviction verhindert Speicherfehler bei vollem Cache |
| **Redis Queue** | ⚠️ Gleiche Redis-Instanz wie Cache | ✅ Dedizierter `redis-queue`-Container mit `noeviction`-Policy | erpnext besser – Jobs gehen nie verloren, Redis gibt Fehler statt silent-drop |
| **PDF-Generierung** | ❌ Kein `wkhtmltopdf` / `weasyprint` im Image – PDF-Export schlägt fehl | ✅ `wkhtmltopdf` + `weasyprint` im Dockerfile installiert | In kittner.netcup funktioniert PDF-Export (Print, Report) nicht out-of-the-box |
| **E-Mail-Versand** | ⚠️ Single Worker – E-Mails konkurrieren mit allen anderen Jobs | ✅ `queue-long` verarbeitet E-Mail-Batch-Jobs isoliert | erpnext stabiler bei hohem E-Mail-Aufkommen |
| **Nginx / Static Assets** | ❌ Kein nginx – Traefik leitet direkt an `bench serve:8000` | ✅ Dedizierter `frontend`-Container mit nginx, serviert Assets aus eigenem Volume direkt | erpnext deutlich schneller bei statischen Assets (JS, CSS, Bilder) |
| **Konfiguration (`bench set-config`)** | ✅ In `entrypoint.sh` inline bei erstem Start | ✅ Dedizierter `configurator`-One-Shot-Container | Beide funktional; erpnext klarer getrennt |
| **Site-Erstellung** | ✅ In `entrypoint.sh` inline, erkennt existing site | ✅ Dedizierter `create-site`-Container, erkennt existing site | Beide funktional; erpnext klarer getrennt |
| **App-Installation** | ✅ `install_apps.sh` – Install + Deinstall nicht genutzter Apps | ✅ `install_upgrade_apps.sh` – Install + Upgrade + Migrate + Cache-Clear + Developer-Mode | erpnext vollständiger Lifecycle |
| **Developer-Mode** | ❌ Nicht gesetzt | ✅ `bench set-config developer_mode 1` in `install_upgrade_apps.sh` | Relevant für Asset-Reload ohne Build-Step |
| **SSL / HTTPS** | ✅ `bench set-config webserver_port 443` + `use_ssl 1` + Traefik TLS-Termination | ✅ Traefik TLS-Termination + `FRAPPE_SITE_NAME_HEADER` in nginx | Beide korrekt; Ansatz unterschiedlich |
| **host_name-Konfiguration** | ✅ `bench set-config host_name https://${SITE_NAME}` – explizit in entrypoint.sh | ✅ Per nginx env var `FRAPPE_SITE_NAME_HEADER` | Beide korrekt |
| **Startup-Reihenfolge** | ✅ `depends_on` + INITED-File-Polling + `common_site_config.json`-Check | ✅ `wait-for-it` für DB/Redis + `common_site_config.json`-Polling | Beide haben Healthchecks; kittner.netcup nutzt init-Container, erpnext `wait-for-it` |
| **Restart Policy** | ⚠️ `restart: unless-stopped` für alle Services (auch One-Shot!) | ✅ `restart_policy: on-failure` für Services, `none` für One-Shot | erpnext präziser – verhindert endlose Restarts von init-Containern |
| **DB Wildcard-Fix** | ✅ `direct_wildcard_fix.sh` – in entrypoint.sh aufgerufen | ✅ Portiert in `create-site`-Container (umgesetzt in Prio-1-Task) | Beide jetzt korrekt |

### Kritische Lücke in kittner.netcup: WebSocket fehlt

Das Procfile in `entrypoint.sh` wird bewusst minimalistisch geschrieben:
```sh
echo "web: bench serve --port 8000" > Procfile
```
`bench start` startet dann **nur** den Web-Server – kein `socketio.js`, kein Socket-IO-Prozess. Damit fehlen in kittner.netcup:
- Echtzeit-Benachrichtigungen (Doctype-Änderungen, Notifications)
- Progress-Indikatoren (Importe, Reports, lange Jobs)
- Live-Collaboration-Features
- WebSocket-basierte Background-Job-Status-Updates

### Kritische Lücke in kittner.netcup: Dev-Server statt Gunicorn

`bench serve` ist der Frappe Development Server – single-threaded, ohne Worker-Pool, nicht für Produktion ausgelegt. erpnext_infrastructure nutzt Gunicorn mit 2 Workers × 4 Threads = bis zu 8 parallele Requests.

---

## Was ist wo besser?

### Besser in `kittner.netcup`

1. **`direct_wildcard_fix.sh`** – löst ein reales operatives Problem: Wenn sich die Container-IP ändert, schlagen MySQL-Verbindungen mit IP-spezifischen Users fehl. Der Wildcard-Fix klont User-Einträge mit `host='%'`.
2. **`cleanup_wildcard_permissions.sh`** – Gegenstück für Tests/Bereinigung.
3. **`fix-git-refs.sh`** – robusteres Git-Handling: konfiguriert explizit alle Remote-Refs, bevor auf Branches/Tags ausgecheckt wird.
4. **Site-Name-Erkennung** in `entrypoint.sh` – liest den aktuellen Default-Site-Namen aus `common_site_config.json`, statt blind `SCENARIO_TRAEFIK_URL` zu verwenden. Verhindert Probleme bei URL-Änderungen.
5. **Einfachere Architektur** – weniger Container = weniger Startabhängigkeiten, einfacheres Debugging.
6. **`docker compose`** (ohne Bindestrich) – aktueller CLI-Standard.

### Besser in `erpnext_infrastructure`

1. **Vollständiger Dockerfile-Build** – kein Abhängigkeit von `frappe/bench:latest` (das sich jederzeit ändern kann), volle Kontrolle über alle Abhängigkeiten.
2. **wkhtmltopdf + weasyprint** – PDF-Generierung out-of-the-box, in Produktion essentiell.
3. **Restic im Image** – Backup-Tooling direkt verfügbar.
4. **Granulare Volumes (8 statt 3)** – erlaubt selektive Restores, separate Rotation von logs vs. sites vs. db, unabhängige Backups einzelner Teile.
5. **Dedizierter nginx-Container** mit Security-Headern – production-grade HTTP-Härtung.
6. **Getrennte Redis-Instanzen** (cache + queue) – bessere Ressourcenisolierung, erlaubt unterschiedliche Eviction-Policies.
7. **`install_upgrade_apps.sh`** – vollständiger Lifecycle: Upgrade + `bench migrate` + Cache-Clear + `bench update --requirements` + Developer-Mode.
8. **Node.js via NVM** mit gepinnter Version – reproduzierbare Builds.

---

## Was lohnt sich in `erpnext_infrastructure` umzusetzen?

### Priorität 1 – Sicherheit / Stabilität

- [x] **`direct_wildcard_fix.sh` übernehmen** (aus kittner.netcup kopieren und in den `create-site`-Container oder ein Init-Script integrieren). Das Problem tritt in jedem containerisierten Setup auf, bei dem sich Container-IPs nach einem Neustart ändern.

- [x] **Hardcodiertes `MYSQL_ROOT_PASSWORD: admin` durch `${DB_ROOT_PASSWORD}` ersetzen** (aktuell in `docker-compose.yml` des `db`-Services). Das ist ein klares Sicherheitsproblem.

- [x] **`docker-compose` → `docker compose`** in `scenario.sh` aktualisieren (deprecated seit Docker 20.10).

### Priorität 2 – Robustheit

- [x] **`fix-git-refs.sh` übernehmen** und in `install_upgrade_apps.sh` integrieren. Verhindert `fatal: couldn't find remote ref`-Fehler bei ungewöhnlichen Branch-/Tag-Konstellationen.

- [x] **Site-Name-Erkennung** aus `entrypoint.sh` (kittner.netcup) in den `create-site`-Container portieren: aktuellen Default-Site-Namen aus `common_site_config.json` lesen, statt immer `SCENARIO_TRAEFIK_URL` zu vertrauen.

### Priorität 3 – Nice-to-have

- [x] **`cleanup_wildcard_permissions.sh`** als optionales Debug/Test-Tool einfügen.
- [x] `DB_ROOT_USER` als separate Umgebungsvariable führen (kittner.netcup hat das bereits, erpnext_infrastructure verwendet überall nur `root` implizit).

### Weitere TODOs

- [x] T.1 Apps to install sollen nicht in einer variable sein, sondern in einem JSON file im gleichnamigen scenario verzeichnis
  - [x] Das heißt die variable soll weiterhin funktionieren
  - [x] Hat die variable den filename des JSON, dann soll aus dem JSON geladen werden.
  - [x] wenn die vaiable die daten enthält (ohne JSON), soll der JSON inhalt und eine kurze anleitung geprintet werden.
- [x] T.2 Die apps (und auch erpnext und frappe) sollen mit einer bestimmten version installiert werden können, nicht nur mit einem branch.
- [ ] T.3 die Versionsnummern sollen per skript auf die aktuellsten geupdatet werden können
