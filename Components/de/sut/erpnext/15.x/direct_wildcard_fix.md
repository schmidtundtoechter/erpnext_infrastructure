# direct_wildcard_fix.sh

## Zweck
`direct_wildcard_fix.sh` repariert MariaDB-Benutzerrechte fuer Frappe-DB-User, wenn Container-IPs wechseln.

Typischer Fehler ohne Fix:
- `Access denied for user '_<hash>'@'172.x.x.x'`

Hintergrund:
- Bei `down`/`up` oder `docker compose run --rm` bekommen Container oft neue interne IPs.
- DB-User und Grants liegen dauerhaft in der DB (Volume), die Container-IP aber nicht.
- Host-gebundene Eintraege (z. B. nur fuer alte IP) passen dann nicht mehr.

## Was das Script macht
1. Wartet auf MariaDB-Verfuegbarkeit.
2. Liest alle Frappe-User (`mysql.user`, Name beginnt mit `_`).
3. Prueft, ob fuer jeden User ein Wildcard-Hosteintrag (`user@'%'`) mit Passwort existiert.
4. Wenn nicht vorhanden/defekt:
- Kopiert Auth-Plugin und Passwort-Hash von einem vorhandenen Hosteintrag.
- Erstellt/repariert `user@'%'`.
- Setzt DB-Grants fuer die gefundenen Datenbanken.
5. Fuehrt `FLUSH PRIVILEGES` aus.
6. Testet Verbindung mit `db_password` aus `site_config.json`.

## Wann ausfuehren
- Nach `init`/`create-site` (automatisch im Compose-Flow).
- Vor kritischen Schritten mit DB-Zugriff aus kurzlebigen Containern, z. B. `backup`, `migrate`, `install`.
- Nach Restore, wenn DB-User/Host-Eintraege inkonsistent sind.

## Warum fuer Backup relevant
`bench --site <site> backup` verbindet sich mit dem Site-DB-User aus `site_config.json`.
Wenn dieser User nicht von der aktuellen Container-Herkunft (Host/IP) darf, bricht Backup mit `Access denied` ab.

## Sicherheitshinweis
`user@'%'` ist robust gegen wechselnde Container-IPs, aber weiter gefasst als host-spezifische Eintraege.
In abgeschotteten internen Docker-Netzen ist das oft akzeptabel.
Wenn gewuenscht, kann spaeter auf Netzwerk-Pattern (z. B. `172.18.%`) eingegrenzt werden.

## Troubleshooting
- Fehler: `Access denied ...`
- Pruefen:
  - Gibt es `user@'%'` in `mysql.user`?
  - Hat der Eintrag ein `authentication_string`?
  - Stimmt `db_password` in `sites/<site>/site_config.json`?
  - Sind Grants in `mysql.db` fuer den User vorhanden?
- Danach Script erneut ausfuehren und den Verbindungstest im Output pruefen.

## Zugehoerige Dateien
- Script: `direct_wildcard_fix.sh`
- Cleanup/Test-Script: `cleanup_wildcard_permissions.sh`
- Aufrufer: `docker-compose.yml` (Service `create-site`) und `scenario.sh` (Backup-Flow)
