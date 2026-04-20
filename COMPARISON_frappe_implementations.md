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

- [ ] **`direct_wildcard_fix.sh` übernehmen** (aus kittner.netcup kopieren und in den `create-site`-Container oder ein Init-Script integrieren). Das Problem tritt in jedem containerisierten Setup auf, bei dem sich Container-IPs nach einem Neustart ändern.

- [ ] **Hardcodiertes `MYSQL_ROOT_PASSWORD: admin` durch `${DB_ROOT_PASSWORD}` ersetzen** (aktuell in `docker-compose.yml` des `db`-Services). Das ist ein klares Sicherheitsproblem.

- [ ] **`docker-compose` → `docker compose`** in `scenario.sh` aktualisieren (deprecated seit Docker 20.10).

### Priorität 2 – Robustheit

- [ ] **`fix-git-refs.sh` übernehmen** und in `install_upgrade_apps.sh` integrieren. Verhindert `fatal: couldn't find remote ref`-Fehler bei ungewöhnlichen Branch-/Tag-Konstellationen.

- [ ] **Site-Name-Erkennung** aus `entrypoint.sh` (kittner.netcup) in den `create-site`-Container portieren: aktuellen Default-Site-Namen aus `common_site_config.json` lesen, statt immer `SCENARIO_TRAEFIK_URL` zu vertrauen.

### Priorität 3 – Nice-to-have

- [ ] **`cleanup_wildcard_permissions.sh`** als optionales Debug/Test-Tool einfügen.
- `DB_ROOT_USER` als separate Umgebungsvariable führen (kittner.netcup hat das bereits, erpnext_infrastructure verwendet überall nur `root` implizit).
