# Konzept und Architektur für ein Backup- und Restore-System für ERPNext/Frappe

## 1. Zielbild

Ziel ist ein bewusst schlankes, lokal nutzbares System für Backup, Übersicht, Transfer und Restore von ERPNext/Frappe-Sites in einer heterogenen Umgebung.

Die Lösung soll **nicht** als zentrale Plattform oder als zentraler Backup-Server umgesetzt werden, sondern als **lokal ausführbares Bash-Skript bzw. Set von Bash-Skripten**. Die Wahrheit über vorhandene Backups liegt **nicht** in einer zentralen Datenbank oder einem zentralen Repository, sondern verteilt auf den angebundenen Systemen selbst.

Lokal existieren nur:

1. die Skripte
2. eine Konfiguration der bekannten Knoten
3. ein regenerierbarer lokaler Cache über gefundene Backups

Dieses System soll sowohl manuell als auch automatisiert nutzbar sein.

---

## 2. Architekturentscheidungen

Folgende Architekturentscheidungen sind gesetzt:

### 2.1 Lokale Ausführung

Die gesamte Logik läuft lokal auf einem Rechner in Bash.

Es gibt keine zentrale Server-Anwendung, keinen dauerhaft laufenden Dienst und kein zentrales Web-Backend.

### 2.2 Konfigurationsgetriebene Knotenverwaltung

Neben dem Skript gibt es eine Konfiguration, in der alle bekannten Knoten beschrieben sind.

Ein Knoten kann fachlich insbesondere eine der folgenden Quellarten bereitstellen:

* ein Frappe-Bench-Backup-Verzeichnis
* ein einfaches Backup-Verzeichnis

Diese Quellarten koennen technisch in unterschiedlichen Zugriffsformen vorliegen:

* ein lokales Verzeichnis
* ein per SSH erreichbarer Host
* ein Host mit Docker-Containern
* ein Kundensystem mit direktem Host-Zugriff
* ein Kundensystem mit Docker-basiertem ERPNext/Frappe

Die Konfiguration enthält alle Informationen, die nötig sind, um:

* den Knoten zu adressieren
* relevante Backup-Verzeichnisse zu finden
* Bench-Kommandos auszuführen
* bei Docker in den richtigen Container zu gelangen

### 2.3 Kein zentrales Repository

Es gibt bewusst **kein** zentrales Backup-Repository als Single Source of Truth.

Backups verbleiben auf den jeweiligen Systemen oder werden zwischen Systemen direkt übertragen.

Das lokale System verwaltet nur einen Cache, aber kein zentrales Wahrheitsmodell.

### 2.4 Regenerierbarer lokaler Cache

Lokal gibt es einen Cache über bekannte Backups.

Dieser Cache dient nur der Geschwindigkeit, Übersicht und Suchbarkeit.

Er muss jederzeit:

* vollständig löschbar sein
* vollständig neu aufbaubar sein
* rein aus den realen Systemen rekonstruiert werden können

Daraus folgt:

* Der Cache ist ein Arbeitsindex, keine Wahrheit.
* Jede kritische Operation muss gegen den Realzustand prüfbar sein.

---

## 3. Anwendungsfälle

Das System soll mindestens folgende Anwendungsfälle unterstützen:

### 3.1 Backup erzeugen

Auf einem Quellsystem soll für eine bestimmte Site ein vollständiges Backup erzeugt werden.

### 3.2 Backups inventarisieren

Das System soll erkennen, auf welchen bekannten Knoten welche Backups vorhanden sind.

### 3.3 Backups auflisten und filtern

Der Benutzer soll lokal eine Übersicht über gefundene Backups haben, filterbar nach:

* Quelle
* Site
* Datum
* Tag
* Umgebung
* Kundensystem
* Typ

### 3.4 Backup übertragen

Ein Backup soll von einem Quellsystem auf ein Zielsystem kopiert werden können.

### 3.5 Restore ausführen

Ein Backup soll auf einem Zielsystem wieder eingespielt werden können.

### 3.6 Cache neu aufbauen

Der lokale Cache soll aus den realen Knoten neu aufgebaut werden können.

### 3.7 Automatisierung

Die Skripte sollen so gestaltet sein, dass sie durch andere Automatisierungen aufgerufen werden können.

---

## 4. Betriebsumgebung

Die Umgebung umfasst mehrere Systemarten:

### 4.1 Lokale Systeme

* Zugriff direkt lokal
* ERPNext/Frappe ggf. in Docker
* ggf. Test- oder Entwicklungssysteme

### 4.2 Eigene Remote-Systeme

* per SSH erreichbar
* Docker oder Host-basiert
* ein oder mehrere ERP-Systeme pro Maschine

### 4.3 Kundensysteme

* per SSH erreichbar
* teils Docker-basiert
* teils direkt auf der Maschine installiert
* Erreichbarkeit ggf. nur über VPN oder bestimmte Netzpfade

Die Lösung muss alle drei Typen mit einem einheitlichen Modell behandeln.

---

## 5. Grundprinzip der Architektur

Die Architektur besteht logisch aus drei Bausteinen:

## 5.1 Skriptlogik

Ein Bash-Skript oder Set von Bash-Skripten kapselt alle Operationen.

Beispiele:

* `backupctl scan`
* `backupctl create`
* `backupctl list`
* `backupctl copy`
* `backupctl restore`
* `backupctl cache rebuild`
* `backupctl cache clear`

## 5.2 Knotenkonfiguration

Eine deklarative Konfigurationsdatei beschreibt die bekannten Knoten.

## 5.3 Lokaler Cache

Ein lokaler Datenbestand hält Informationen über zuletzt gefundene Backups.

---

## 6. Konfigurationsmodell

Die Konfiguration ist das Herzstück des Systems. Sie beschreibt, **wo** und **wie** das Skript mit Knoten interagiert.

Ein Knoten sollte mindestens diese Informationen enthalten:

* Knotenname
* Quellart: `frappe-backup-dir`, `plain-backup-dir`
* Zugriffstyp: `local`, `local-docker`, `ssh-host`, `ssh-docker`
* Hostname oder lokaler Pfad
* SSH-User
* SSH-Port
* optional VPN-Hinweis
* Pfad zum Bench oder zu den Sites
* Backup-Verzeichnisse
* Containername oder Compose-Service
* Art der Ausführung
* optionale Tags wie `prod`, `test`, `kunde-a`

### 6.1 Beispielhafte Struktur

```yaml
nodes:
  - id: local-dev
    source_kind: frappe-backup-dir
    access_type: local-docker
    base_path: /Users/matthias/projects/frappe-bench
    bench_path: /Users/matthias/projects/frappe-bench
    backup_paths:
      - /Users/matthias/projects/frappe-bench/sites/*/private/backups
    container: backend
    tags: [local, dev]

  - id: own-prod-01
    source_kind: frappe-backup-dir
    access_type: ssh-docker
    host: own-prod-01.example.net
    port: 22
    user: frappe
    bench_path: /home/frappe/frappe-bench
    backup_paths:
      - /home/frappe/frappe-bench/sites/*/private/backups
    container: erpnext-python
    tags: [own, prod]

  - id: customer-a-prod
    source_kind: frappe-backup-dir
    access_type: ssh-host
    host: customer-a.example.net
    port: 22
    user: frappe
    bench_path: /opt/frappe-bench
    backup_paths:
      - /opt/frappe-bench/sites/*/private/backups
    tags: [customer-a, prod]

  - id: archive-share
    source_kind: plain-backup-dir
    access_type: ssh-host
    host: archive.example.net
    port: 22
    user: backup
    backup_paths:
      - /srv/customer-backups
    tags: [archive]
```

### 6.2 Ziel der Konfiguration

Die Konfiguration soll dem Skript erlauben:

* Kommandos im richtigen Kontext auszuführen
* Dateien an den richtigen Orten zu suchen
* lokal, remote, host-basiert und docker-basiert einheitlich zu behandeln
* zwischen Frappe-Backup-Quellen und einfachen Backup-Verzeichnissen zu unterscheiden

---

## 7. Ausführungsmodell für Knoten

Damit alle Knoten gleich behandelt werden können, braucht das Skript ein internes Laufzeitmodell.

Dabei ist zwischen Quellart und Zugriffspfad zu unterscheiden:

* Die Quellart beschreibt, ob das Tool mit einem Frappe-Bench-Backup-Verzeichnis oder mit einem einfachen Backup-Verzeichnis arbeitet.
* Der Zugriffspfad beschreibt, ob lokal, lokal in Docker, per SSH oder per SSH plus Docker gearbeitet wird.

### 7.1 Lokaler Host

Kommandos werden direkt lokal ausgeführt.

### 7.2 Remote Host per SSH

Kommandos werden per SSH auf dem Host ausgeführt.

### 7.3 Docker auf Host

Kommandos werden auf dem Host adressiert und dann per `docker exec` oder `docker compose exec` in den relevanten Container weitergeleitet.

### 7.4 Abstraktion

Konzeptionell braucht das Skript eine Art Runner-Funktion:

```bash
run_on_node <node> <command>
```

Diese Funktion entscheidet intern:

* lokal oder SSH
* Host oder Docker
* welche Shell-Ebene benutzt wird
* wo Bench-Kommandos ausgeführt werden

---

## 8. Backup-Modell

Ein vollständiges ERPNext/Frappe-Backup soll aus vier fachlichen Bestandteilen bestehen:

1. Datenbank
2. Public Files
3. Private Files
4. Site Config

### 8.1 Erwartete Artefakte

* Datenbank-Dump
* Archiv der Public Files
* Archiv der Private Files
* `site_config.json`

Ergänzend sollte das System drei weitere technische Dateien erzeugen:

* Manifest-Datei (Beispiel: manifest.json)
* Checksum-Datei (Beispiel: checksums.sha256)
* Apps-/Versions-Metadaten (Beispiel: apps.json)

### 8.2 Erzeugung

Die Sicherung erfolgt auf dem Quellsystem im Kontext der konkreten Site.

Bei Frappe/ERPNext ist das fachlich typischerweise:

* `bench --site <site> backup --with-files`

Zusätzlich wird `site_config.json` separat aufgenommen.

### 8.3 Portable Backup-Einheit

Für die Logik des Skripts ist ein Backup eine zusammengehörige Menge von Dateien, nicht nur eine einzelne Datei.

Das Skript muss diese Einheit als ein Backup-Objekt behandeln.

## 8.4 Rückwärtskompatibilität

Das System sollte auch standardmäßig erzeugte backups lesen, auflisten und Informationen darüber im lokalen cache speichern können.

---

## 9. Benennung und Metadaten

Ein eigenes, informationsreiches Dateinamensschema ist für diese Architektur nicht zwingend erforderlich.

Da das System ausdrücklich mit Standard-Backups von Frappe kompatibel bleiben soll, ist es sinnvoller, die von Frappe erzeugten Dateinamen und die bestehende Backup-Struktur beizubehalten und zusätzliche Informationen strukturiert in Metadaten abzulegen.

### 9.1 Grundsatz

Standardmäßig werden die von Frappe erzeugten Backup-Dateien nicht umbenannt.

Das betrifft insbesondere:

* Datenbank-Dump
* Public-Files-Archiv
* Private-Files-Archiv
* die übliche Ablagestruktur unterhalb des Site-Backup-Verzeichnisses

### 9.2 Zusätzliche Informationen

Informationen, die für Verwaltung, Suche und Restore wichtig sind, gehören nicht primär in den Dateinamen, sondern in strukturierte Metadaten.

Dazu gehören insbesondere:

* Zeitpunkt
* Ursprungssystem
* Ursprungs-Site
* Art des Backups
* fachlicher Grund des Backups
* Benutzer-Tags
* Apps- und Versionsinformationen
* Prüfsummen
* Vollständigkeitsstatus

### 9.3 Manifest als primärer Metadatenträger

Zu jedem logisch zusammengehörigen Backup soll das Tool eine Manifest-Datei erzeugen oder pflegen, zum Beispiel `manifest.json`.

Diese Datei ist der primäre Träger der zusätzlichen Informationen, die nicht bereits aus den Standarddateien von Frappe ableitbar sind.

Beispielhafte Inhalte:

* `backup_id`
* `created_at`
* `source_node`
* `source_site`
* `backup_type`
* `reason`
* `tags`
* `artifacts`
* `checksums`
* `apps`
* `complete`

### 9.4 Tags

Freie Tags bleiben sinnvoll, aber sie sollen als Metadaten im Manifest und im lokalen Cache geführt werden, nicht als Pflichtbestandteil eines speziellen Dateinamens.

Beispiele:

* `prod`
* `pre-update`
* `before-migration`
* `release-15-62`
* `kundenfreigabe`

### 9.5 Verpflichtender Grundtext

Zusätzlich zu optionalen Tags sollte beim Erzeugen eines Backups ein fachlicher Grundtext verpflichtend angegeben werden.

Dieser Grundtext beschreibt den Anlass oder Zweck des Backups in freier Form und dient später als wichtigste menschlich lesbare Einordnung.

Typische Beispiele:

* `taegliches Backup`
* `vor Demo fuer Kunde A`
* `vor Update auf ERPNext 15.62`
* `nach Datenkorrektur Debitoren`
* `vor Migration Test nach Produktion`

Der Grundtext ist damit fachlich naeher an einem Anzeigenamen oder Titel des Backups als an einem technischen Dateinamen.

Er soll im Manifest und im lokalen Cache gespeichert werden und in Listenansichten gut sichtbar sein.

### 9.6 Interne Identifikation

Für die interne Verarbeitung sollte das Tool mit einer stabilen `backup_id` arbeiten.

Die `backup_id` identifiziert die zusammengehörige Backup-Einheit unabhängig davon, wie die einzelnen physischen Dateien heißen.

### 9.7 Optional lesbare Namen

Falls für manuelle Arbeitsschritte ein besser lesbarer Anzeigename hilfreich ist, kann das Tool einen abgeleiteten Anzeigenamen erzeugen oder im Cache führen.

Dieser Anzeigename ist jedoch nur eine Benutzerhilfe und nicht die technische Identität des Backups.

---

## 10. Lokaler Cache

## 10.1 Zweck

Der lokale Cache ist eine Arbeitskopie der zuletzt bekannten Backup-Landschaft.

Er dient dazu:

* Backups schneller aufzulisten
* Filterung zu ermöglichen
* Transfers und Restore-Auswahl zu erleichtern
* Scans nicht immer vollständig neu ausführen zu müssen

## 10.2 Nicht-Zweck

Der Cache ist **nicht** die Wahrheit.

Er darf niemals so gebaut werden, dass das System ohne ihn nicht mehr arbeitsfähig ist.

## 10.3 Inhalt

Der Cache kann enthalten:

* Knoten-ID
* Site
* Backupname
* Dateien
* Zeitstempel
* Pfade
* Größe
* Tags
* letzte Sichtung
* Prüfsummen optional

## 10.4 Form

Für Bash ist realistisch:

* JSON-Datei
* mehrere JSON-Dateien
* CSV/TSV
* dateibasiertes Verzeichnis je Backup

Empfehlung für ein Bash-nahes System:

* Konfiguration in YAML oder JSON
* Cache in JSON Lines oder JSON
* Verarbeitung mit `jq`

## 10.5 Regenerierbarkeit

Es muss Kommandos geben für:

* Cache löschen
* Cache vollständig neu scannen
* Cache inkrementell aktualisieren

Beispiel:

```bash
backupctl cache clear
backupctl cache rebuild
backupctl scan --node customer-a-prod
```

---

## 11. Scan- und Discovery-Konzept

Da die Wahrheit verteilt im System liegt, ist der Scan ein Kernprozess.

## 11.1 Scan-Ziel

Erkennen, welche Backups auf welchen Knoten tatsächlich vorhanden sind.

## 11.2 Suchorte

Die Suchorte kommen aus der Knotenkonfiguration.

Dabei sind mindestens zwei Quellarten zu unterscheiden.

### A. Frappe-Bench-Backup-Verzeichnis

Typischerweise:

* `sites/*/private/backups`
* zusätzliche definierte Archivverzeichnisse
* optionale manuelle Transfer-Ziele

Diese Quellart kann lokal, lokal in Docker, per SSH oder per SSH plus Docker angesprochen werden.

### B. Einfaches Backup-Verzeichnis

Typischerweise:

* ein lokales Verzeichnis mit bereits exportierten Backup-Dateien
* ein per SSH erreichbares Verzeichnis mit bereits exportierten Backup-Dateien

Diese Quellart ist bewusst einfacher und benoetigt keinen Bench-Kontext.

Sie dient vor allem dazu, bereits erzeugte oder manuell abgelegte Backups zu inventarisieren und weiterzuverteilen.

## 11.3 Ergebnis

Der Scan soll pro Backup mindestens feststellen:

* Knoten
* Site
* Dateiname
* Backupzeitpunkt
* vorhandene Teil-Dateien
* Größe
* letzte Sichtung

## 11.4 Validierung

Der Scan sollte erkennen, ob ein Backup vollständig ist.

Ein vollständiges Backup liegt nur vor, wenn die erwarteten Bestandteile vorhanden sind.

---

## 12. Backup erzeugen

## 12.1 Ablauf

1. Knoten wählen
2. Site wählen
3. Ziel-Tag optional angeben
4. im richtigen Kontext sichern
5. entstandene Artefakte erfassen
6. Cache aktualisieren

## 12.2 Vorprüfungen

Vor einem Backup sollte geprüft werden:

* Knoten erreichbar
* Site vorhanden
* Bench erreichbar
* bei Docker: Container vorhanden
* Backupverzeichnis vorhanden oder erzeugbar
* freier Speicher plausibel

## 12.3 Ergebnis

Das Ergebnis ist ein reales Backup auf dem Quellsystem und ein lokaler Cache-Eintrag.

---

## 13. Backups auflisten

Die Auflistung erfolgt aus dem Cache, optional mit Live-Abgleich.

### 13.1 Modi

* schneller Listenmodus aus Cache
* verifizierter Listenmodus mit Live-Check

### 13.2 Filter

* nach Knoten
* nach Site
* nach Tag
* nach Zeitraum
* nach Umgebung
* nach Vollständigkeit

---

## 14. Backup übertragen

Da kein zentrales Repository existiert, ist die direkte Übertragung zwischen Knoten zentral.

## 14.1 Varianten

### A. Remote nach lokal

Backup von Quellsystem lokal holen

### B. Lokal nach remote

Lokal vorhandenes Backup auf Zielsystem schieben

### C. Remote nach remote über lokalen Orchestrator

Quelle lesen, lokal zwischenspeichern oder streamen, dann auf Ziel schieben

## 14.2 Technische Mittel

Primär soll `rsync` verwendet werden.

`scp` ist nur ein Fallback für Fälle, in denen `rsync` auf einem beteiligten Remote-System nicht verfügbar ist.

* `scp`
* `rsync`
* `sftp`

Für diese Architektur ist `rsync` der bevorzugte Standard, weil damit Übertragungen robuster, nachvollziehbarer und bei Wiederholungen effizienter durchgeführt werden können.

Das Tool sollte daher vor einem Transfer prüfen, ob `rsync` auf Quelle und Ziel verfügbar ist.

Falls `rsync` auf einem beteiligten Remote-System nicht vorhanden ist, darf kontrolliert auf `scp` zurückgefallen werden.

`sftp` ist hier höchstens ein Sonderfall, aber nicht der vorgesehene Standardpfad.

## 14.3 Prinzip

Das Skript orchestriert den Transfer. Es hält nicht selbst dauerhaft die zentrale Kopie als Wahrheit.

Optional kann lokal ein temporärer Arbeitsbereich existieren.

---

## 15. Restore-Konzept

Der Restore ist die kritischste Operation und muss standardisiert sein.

## 15.1 Ziel

Ein ausgewähltes Backup wird auf einem Zielsystem für eine Ziel-Site wieder eingespielt.

## 15.2 Typische Schritte

1. Zielsystem adressieren
2. Backup auf Ziel verfügbar machen
3. im richtigen Kontext `bench restore` ausführen
4. Dateien wiederherstellen
5. `site_config.json` passend behandeln
6. Ziel-Site anpassen
7. Nacharbeiten und Prüfschritte ausführen

## 15.3 Restore-Varianten

### A. Restore in bestehende Site

Bestehende Site wird überschrieben.

### B. Restore als neue Site

Backup wird als neue Site eingespielt.

### C. Restore mit Umbenennung

Quelle und Ziel haben unterschiedliche Site-Namen oder andere Zielparameter.

---

## 16. Behandlung von `site_config.json`

Die `site_config.json` gehört fachlich zum Backup, darf aber nicht in jedem Fall blind 1:1 übernommen werden.

### 16.1 Grund

In der Site-Config können enthalten sein:

* Datenbankname
* Datenbankpasswort
* Host-spezifische Angaben
* Umgebungsparameter
* Integrationsparameter
* Secrets

### 16.2 Konsequenz

Das Restore-Konzept braucht drei Modi:

* `use-source-config` nur in Sonderfällen
* `merge-config` als Standard
* `keep-target-config` für bestimmte Zielumgebungen

### 16.3 Empfehlung

Standardmäßig sollte die Site-Config **kontrolliert gemerged** werden.

---

## 17. Nacharbeiten nach dem Restore

Ein Restore ist nicht mit dem Datenimport beendet.

Typische Nacharbeiten:

* Site-Konfiguration prüfen
* Berechtigungen prüfen
* Bench-Migration ausführen
* Dienste/Container neu starten, falls nötig
* Erreichbarkeit testen
* Dateipfade prüfen
* Scheduler/Jobs prüfen

Das Skript sollte diese Schritte zumindest teilweise standardisieren.

---

## 18. Restore-Vorprüfungen

Vor jedem Restore soll geprüft werden:

* Zielsystem erreichbar
* Ziel-Site vorhanden oder neu anlegbar
* Zielkontext korrekt
* Backup vollständig
* notwendige Dateien vorhanden
* genügend Speicher auf Ziel vorhanden
* App- und Versionskompatibilität möglichst plausibel

Da das System bewusst schlank bleibt, kann die erste Version diese Prüfungen pragmatisch halten. Trotzdem sollte das Konzept diese Prüfungen vorsehen.

---

## 19. Sicherheits- und Risikobetrachtung

Auch als Bash-System braucht die Lösung klare Leitplanken.

### 19.1 Risiken

* Restore überschreibt produktive Daten
* falscher Knoten wird adressiert
* falscher Container wird genutzt
* unvollständige Backups werden wiederhergestellt
* Site-Config wird falsch übernommen
* Versionen und Apps passen nicht zusammen

### 19.2 Schutzmaßnahmen

* explizite Knoten- und Site-Auswahl
* Sicherheitsabfrage bei produktiven Zielen
* Optionaler Dry-Run-Modus
* Vorprüfungen
* Logging aller Schritte
* klare Trennung zwischen `scan`, `copy`, `restore`
* produktive Restores nur mit explizitem Flag

---

## 20. Logging

Das Skript sollte jeden Vorgang nachvollziehbar protokollieren.

Mindestens:

* Zeitpunkt
* Aktion
* Quellknoten
* Zielknoten
* Site
* Ergebnis
* Exit-Code
* Pfade

Empfehlung:

* menschenlesbares Log
* optional JSON-Log für Automatisierungen

---

## 21. CLI-Konzept

Die Lösung sollte als Kommandozeilenwerkzeug mit Subcommands aufgebaut sein.

### Beispiel

```bash
backupctl nodes list
backupctl scan
backupctl scan --node customer-a-prod
backupctl list
backupctl create --node customer-a-prod --site erp.customer-a.de --tag pre-update
backupctl copy --from customer-a-prod --to own-prod-01 --backup <id>
backupctl restore --node own-prod-01 --site test.customer-a.local --backup <id>
backupctl cache clear
backupctl cache rebuild
```

---

## 22. Empfohlene interne Struktur des Skriptsets

Auch wenn alles in Bash bleibt, sollte es modular aufgebaut sein.

### 22.1 Mögliche Module

* `config.sh` – Konfiguration laden
* `nodes.sh` – Knotenzugriffe
* `scan.sh` – Backup-Discovery
* `backup.sh` – Backup-Erzeugung
* `copy.sh` – Übertragung
* `restore.sh` – Restore-Logik
* `cache.sh` – Cache verwalten
* `log.sh` – Logging
* `main.sh` – CLI-Einstiegspunkt

Alternativ ein einzelnes Skript mit klar getrennten Funktionsbereichen.

---

## 23. Datenfluss

## 23.1 Backup erstellen

Quellsystem → reales Backup im Quellsystem → lokaler Scan/Cache-Eintrag

## 23.2 Backup übertragen

Quelle → lokaler Orchestrator als Steuerinstanz → Ziel

## 23.3 Backup inventarisieren

Knoten scannen → lokale Cache-Datei aktualisieren

## 23.4 Restore

Backup auf Ziel verfügbar machen → Restore im Zielkontext → Nacharbeiten → Verifikation

---

## 24. Warum diese Architektur zur Anforderung passt

Diese Architektur passt zur Anforderung, weil sie:

* keine zentrale Infrastruktur voraussetzt
* lokal ausführbar bleibt
* mit eigener und fremder Infrastruktur umgehen kann
* Docker und Nicht-Docker unterstützt
* automatisierbar bleibt
* die Realität der verteilten Backups respektiert
* mit einem wegwerfbaren Cache arbeitet statt mit einer künstlichen zentralen Wahrheit

---

## 25. Klare Soll-Definition

Das zu bauende System ist ein lokal ausführbares, konfigurationsgetriebenes Bash-Werkzeug für ERPNext/Frappe, das verteilte Backup-Standorte über lokale und per SSH erreichbare Knoten inventarisiert, Backups erzeugt, überträgt und wiederherstellt, dabei Docker- und Host-Installationen einheitlich behandelt und einen vollständig regenerierbaren lokalen Cache als Arbeitsindex verwendet.

---

## 26. Empfohlene nächste Konkretisierung

Auf Basis dieses Konzepts sollten als Nächstes definiert werden:

1. konkretes Format der Knotenkonfiguration
2. konkretes Format des lokalen Cache
3. CLI-Befehle und Argumente
4. Ablaufdiagramme für `scan`, `create`, `copy`, `restore`
5. Regeln für Backup-Erkennung und Backup-Vollständigkeit
6. Regeln für die Behandlung von `site_config.json`
7. Standard-Logging und Exit-Codes

---

## 27. MVP-Schnitt

Ein pragmatischer MVP sollte zuerst nur Folgendes können:

* Knoten aus Konfiguration lesen
* bekannte Backup-Verzeichnisse scannen
* lokalen Cache aufbauen
* Backups listen
* Backup auf Quellsystem erzeugen
* Backup von A nach B kopieren
* Restore auf Zielsystem ausführen

Erst danach sollten ergänzt werden:

* Tagging-Metadaten
* Prüfsummen
* Live-Validierung
* Dry-Run
* Sicherheitsabfragen für produktive Systeme
* inkrementelle Cache-Updates

---

## 28. Architektur-Kurzfassung

### Festgelegt

* lokal laufendes Bash-Skript oder Skriptset
* deklarative Konfiguration der Knoten
* kein zentrales Backup-Repository
* lokaler, regenerierbarer Cache

### Unterstützte Umgebungen

* lokal
* SSH
* SSH plus Docker
* eigene Systeme
* Kundensysteme

### Kernoperationen

* scan
* create backup
* list
* copy
* restore
* cache clear
* cache rebuild

### Grundprinzip

Nicht der lokale Cache ist die Wahrheit, sondern die real verteilten Backup-Bestände auf den angebundenen Systemen.
