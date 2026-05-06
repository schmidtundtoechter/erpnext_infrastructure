# Konzept: Restart vs. Update trennen

Ziel: Ein normales `down,up` soll das System nicht aktualisieren. Es soll nur Container neu starten und den App-Installationsstatus an `apps.json` angleichen. Ein echtes Update wird weiterhin ueber den `update`-Step vorbereitet und technisch ausgeloest.

## Ziel-Semantik

### `up`

`up` ist ein normaler Start-/Restart-Pfad.

Er soll:

- Data-Volumes pruefen/anlegen wie bisher.
- `docker compose up -d` ausfuehren.
- Keine expliziten Image-Pulls machen.
- Kein `docker compose build --pull` ausfuehren.
- Kein App-Upgrade ausfuehren.
- App-Installationsstatus reconciliieren:
  - Apps installieren, die laut `apps.json` aktiv sein sollen, aber noch fehlen.
  - Apps deinstallieren/entfernen, die laut `apps.json` nicht aktiv sein sollen oder nicht mehr in der aktiven Liste stehen.
  - Bereits installierte aktive Apps unveraendert lassen.

Wichtig: `up` soll nicht mit `--no-build` laufen. Wenn das lokale Image noch nicht existiert, darf Docker Compose es bauen. Wenn das Image existiert, soll kein Pull oder Build-Pull erzwungen werden.

### `down`

`down` bleibt ein reiner Stop-/Remove-Pfad fuer Container.

Er soll:

- Data-Volumes nur mit `nocreate` pruefen.
- Container stoppen und entfernen.
- Keine Volumes entfernen.
- Keine App- oder Image-Aenderungen ausloesen.

### `update`

`update` bleibt der bewusste Update-Pfad.

Er soll weiterhin:

- `apps.json` lesen.
- Versionsvorschlaege erzeugen.
- `apps.updated.json` schreiben.
- Vorschlaege fuer `FRAPPE_VERSION` und `ERPNEXT_VERSION` ausgeben.

Zusaetzlich soll `update` der einzige Step werden, der explizit Docker-Images aktualisiert:

- `docker compose pull`
- `docker compose build --pull`

Danach hinterlegt `update` eine temporaere Marker-Datei in einem persistenten Bench-Unterverzeichnis, damit der naechste Lauf von `install_upgrade_apps.sh` im Upgrade-Modus arbeitet.

## App-Management-Modi

`install_upgrade_apps.sh` wird in zwei Modi aufgeteilt:

- `reconcile`
- `upgrade`

Der Modus wird nicht dauerhaft in `.env` gespeichert. Stattdessen entscheidet das Script anhand einer Marker-Datei in einem persistenten Bench-Unterverzeichnis.

Vorschlag:

```text
<bench>/sites/.run-app-upgrade
```

Wenn die Datei existiert, laeuft `install_upgrade_apps.sh` im Modus `upgrade`.
Wenn die Datei nicht existiert, laeuft es im Modus `reconcile`.

Nach einem erfolgreichen Upgrade loescht `install_upgrade_apps.sh` diese Datei wieder.

## Modus `reconcile`

Das ist der Default fuer jedes normale `up`.

Ablauf:

1. `apps.json` lesen.
2. `frappe` und `erpnext` als immer zu behalten markieren.
3. Fuer jede App in `apps.json`:
   - `active=false`: App deinstallieren/entfernen.
   - `active=true` und App fehlt: App mit der konfigurierten Version installieren.
   - `active=true` und App ist bereits installiert: nichts upgraden.
4. App-Verzeichnisse unter `apps/*`, die nicht mehr aktiv sein sollen, entfernen/deinstallieren.

Nicht ausfuehren:

- kein `git fetch`
- kein `git checkout` fuer bereits vorhandene Apps
- kein `git reset --hard`
- kein `bench update --requirements`
- kein globales `pip install --upgrade`
- kein pauschales `bench migrate`
- kein `bench setup requirements --dev`

Falls eine App neu installiert wurde, kann danach gezielt ein `bench --site <site> migrate` sinnvoll sein. Das ist keine Versionsaktualisierung bestehender Apps, sondern Abschluss der Neuinstallation.

## Modus `upgrade`

Dieser Modus laeuft nur, wenn die Marker-Datei existiert.

Ablauf:

1. `apps.json` lesen.
2. Apps mit `active=false` deinstallieren/entfernen.
3. Aktive Apps installieren oder auf die konfigurierte Version bringen:
   - fehlende App: `bench get-app ... --branch <version>`
   - vorhandene App: `git fetch`, `git checkout`, bei Branch-Refs `git reset --hard <remote>/<version>`
4. Nicht mehr aktive App-Verzeichnisse entfernen.
5. Requirements aktualisieren.
6. Site migrieren.
7. Cache leeren.
8. Marker-Datei loeschen.

Optional weiterhin im Upgrade-Modus:

- `bench set-config -g developer_mode 1`
- `bench set-config -g server_script_enabled 1`
- `bench setup requirements --dev`

Diese Punkte sollten spaeter separat bewertet werden, weil sie produktionsrelevant sind und nicht zwingend Teil jedes Updates sein muessen.

## Neuer Ablauf von aussen

### Normaler Restart ohne Update

```bash
scenario.deploy <scenario> down,up
```

Effekt:

- Container werden gestoppt und neu gestartet.
- Keine expliziten Docker-Pulls.
- Kein `build --pull`.
- Keine App-Upgrades.
- Nur App-Installationsstatus wird reconciliiert.

### Update vorbereiten und ausloesen

```bash
scenario.deploy <scenario> init,update
```

Effekt:

- Versionsvorschlaege werden erzeugt.
- Docker-Images werden gepullt.
- ERPNext-Image wird mit `--pull` neu gebaut.
- Marker-Datei `sites/.run-app-upgrade` wird in der Bench hinterlegt.

Danach muss ein `down,up` stattfinden, damit der einmalige `create-site`-Container neu erzeugt wird und damit `install_upgrade_apps.sh` erneut ausgefuehrt wird:

```bash
scenario.deploy <scenario> down,up
```

Effekt:

- `create-site` startet.
- `install_upgrade_apps.sh` sieht die Marker-Datei.
- App-Upgrades, Requirements und Migration laufen.
- Marker-Datei wird nach erfolgreichem Upgrade geloescht.

Alternativ kann ein Wrapper-Skript spaeter daraus einen zusammenhaengenden Ablauf machen:

```bash
scenario.deploy <scenario> init,update,down,up
```

oder lokal:

```bash
scenario.update <scenario>
```

Dann sollte dieses Wrapper-Skript intern `init,update,down,up` ausfuehren, nicht `stop,init,up`.

## Offene Implementierungsdetails

- Die Marker-Datei sollte nicht direkt unter `<bench>/.run-app-upgrade` liegen, weil der Bench-Root selbst nicht als Volume gemountet ist. Persistente und zwischen Containern sichtbare Kandidaten sind `sites`, `apps`, `env`, `logs` oder `assets`; bevorzugt wird `sites/.run-app-upgrade`.
- `update` laeuft in `scenario.sh` auf dem Remote-Server. Die Marker-Datei sollte nicht direkt ueber den Host-Mountpoint geschrieben werden, weil das Sites-Verzeichnis ein Docker-Volume/Mountpoint sein kann. Stattdessen sollte `update` nach dem Build einen kurzlebigen Container starten, der dasselbe Sites-Volume gemountet hat und dort `sites/.run-app-upgrade` schreibt, z. B. ueber `docker compose run --rm --no-deps --entrypoint bash frontend -lc "touch sites/.run-app-upgrade"`.
- Wenn `update` nur baut und pullt, aber danach kein `up` kommt, bleibt die Marker-Datei liegen. Das ist gewollt: Der naechste `up` fuehrt dann den noch ausstehenden App-Upgrade-Teil aus.
- Wenn ein Upgrade fehlschlaegt, sollte die Marker-Datei nicht geloescht werden. So bleibt sichtbar, dass das Upgrade nicht abgeschlossen wurde und beim naechsten Lauf erneut versucht wird.
