# Deployment-Prozess

Branch-basierter Deployment-Prozess mit 4 Stages.

---

## Branching-Modell

```
main
 └── staging
      └── development
            └── feature/<name>
            └── fix/<name>
```

- **`main`** ist der produktionsreife Stand. Jeder Merge auf `main` löst ein automatisches Deployment auf dem Produktionssystem aus.
- **`staging`** ist der Abnahme-Branch für den Kunden. Ein Merge auf `staging` löst ein automatisches Deployment auf dem Staging-Server beim Kunden aus. Vor dem Deployment wird der Staging-Server auf den aktuellen Stand des Produktionssystems gebracht (Datenkopie aus Production).
- **`development`** ist der Team-Entwicklungsbranch. Feature- und Fix-Branches werden von `development` abgezweigt und per Pull Request zurück nach `development` gemergt. Der `development`-Branch wird auf **test.schmidtundtoechter.com** betrieben und ist dort jederzeit testbar.

---

## Die 4 Stages

### Stage 1 — Lokales Development (Docker)

- Entwicklung findet lokal in einer Docker-Umgebung statt.
- Jedes Feature und jeder Fix bekommt einen eigenen Branch.
- Branch-Namenskonvention: `feature/<kurzer-name>` oder `fix/<kurzer-name>`.
- Commit-Messages folgen dem Format: `<type>: <kurze Beschreibung>` (z. B. `feat: add bench configuration`, `fix: correct SSH key path`).
- Lokale Tests und Syntax-Checks laufen vor dem ersten Push.

### Stage 2 — Test-Server test.schmidtundtoechter.com (development)

- Wenn ein Feature oder Fix bereit ist, wird ein Pull Request von `feature/*` oder `fix/*` nach **`development`** geöffnet.
- Ein Teammitglied führt einen **Code Review** durch und gibt den PR frei.
- Nach dem Merge wird `development` auf **test.schmidtundtoechter.com** aktualisiert.
- Das Team testet die Änderungen dort und stellt sicher, dass alles funktioniert.
- Fehler werden als neuer `fix/*`-Branch behoben und erneut per PR nach `development` gemergt.

### Stage 3 — Staging-Server beim Kunden (staging)

- Wenn der Entwicklungsstand reif für eine Kundenabnahme ist, wird **vor dem Öffnen des PRs** zunächst eine neue Version erzeugt: Versionsnummer erhöhen, CHANGELOG aktualisieren und Git-Tag auf `development` setzen (siehe [Release-Prozess](Release-Prozess.md)).
- Danach wird ein Pull Request von **`development`** nach **`staging`** geöffnet — der PR-Titel trägt die neue Versionsnummer (`Release vX.Y.Z: ...`).
- **Vor dem Deployment** auf `staging` wird der Staging-Server vollständig mit den Daten und dem Stand des Produktionssystems synchronisiert (Produktionsdaten werden auf den Staging-Server kopiert). So testet der Kunde unter realistischen Bedingungen.
- Danach wird `staging` automatisch auf dem Staging-Server des Kunden deployt.
- Der Kunde prüft die Änderungen auf dem Staging-Server.
- Gleichzeitig müssen alle **Integrationstests** sauber durchlaufen.
- Gefundene Fehler werden als `fix/*`-Branch von `development` erstellt, über `development` getestet und erneut per PR nach `staging` gebracht — kein direktes Pushen auf `staging`.

### Stage 4 — Produktion (main)

- Wenn der Kunde die Abnahme erteilt **und** alle Integrationstests grün sind, wird ein Pull Request von **`staging`** nach **`main`** geöffnet.
- Der PR wird von mindestens einem Lead Developer reviewed und freigegeben.
- Nach dem Merge auf `main` wird ein **automatisches Deployment** auf dem Produktionssystem ausgelöst.
- Nach dem Deployment: kurzer Verifikations-Check (Service-Status, Logs, Erreichbarkeit).
- Der Release-Tag wurde bereits beim Staging-PR gesetzt — kein neues Tag erforderlich (siehe [Release-Prozess](Release-Prozess.md)).

---

## Übersicht: Wer deployt wohin

| Branch       | Server                          | Auslöser                       | Vorbedingung                                  |
|:-------------|:--------------------------------|:-------------------------------|:----------------------------------------------|
| `development`| test.schmidtundtoechter.com     | Manuell nach Merge             | Code Review durch Teammitglied                |
| `staging`    | Staging-Server beim Kunden      | Automatisch nach Merge         | Staging-Server mit Produktionsdaten synchronisiert |
| `main`       | Produktionssystem               | Automatisch nach Merge         | Kundenabnahme + Integrationstests grün        |

---

## Hotfix-Prozess

Kritische Produktionsfehler können direkt von `main` abgezweigt werden:

```
main
 └── hotfix/<name>
```

1. Branch `hotfix/<name>` von `main` erstellen.
2. Fix entwickeln und committen.
3. PR nach `main` öffnen (dringend, vereinfachtes Review durch Lead Developer).
4. Nach Merge: automatisches Produktions-Deployment, Patch-Release-Tag setzen.
5. `main` zurück in `staging` und `development` mergen, um Divergenz zu vermeiden.

---

## Deployment-Checkliste

### PR nach `development`
- [ ] Code Review durch Teammitglied durchgeführt und approved
- [ ] Lokale Tests grün

### PR nach `staging`
- [ ] development-Stand auf test.schmidtundtoechter.com getestet
- [ ] Staging-Server mit Produktionsdaten synchronisiert
- [ ] Deployment auf Staging-Server erfolgreich

### PR nach `main`
- [ ] Kundenabnahme auf Staging-Server erteilt
- [ ] Alle Integrationstests grün
- [ ] PR reviewed und approved (Lead Developer)
- [ ] Post-Deployment-Verifikation auf Produktionssystem durchgeführt
- [ ] Release-Tag gesetzt

---

*Zuletzt aktualisiert: Mai 2026*
