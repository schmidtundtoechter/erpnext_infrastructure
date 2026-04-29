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

- **`main`** ist der produktionsreife Stand. Jeder Merge auf `main` löst ein Release aus.
- **`staging`** ist der Integrations-Branch. Änderungen werden hier zusammengeführt und getestet, bevor sie nach `main` gehen.
- **`development`** ist der Team-Entwicklungsbranch. Feature- und Fix-Branches werden von `development` abgezweigt und per PR zurück nach `development` gemergt.

---

## Die 4 Stages

### Stage 1 — Lokales Development (Docker container)

- Entwicklung findet in einem Feature- oder Fix-Branch statt.
- Branch-Namenskonvention: `feature/<kurzer-name>` oder `fix/<kurzer-name>`.
- Lokale Tests und Syntax-Checks laufen vor dem ersten Push.
- Commit-Messages folgen dem Format: `<type>: <kurze Beschreibung>` (z. B. `feat: add bench configuration`, `fix: correct SSH key path`).

### Stage 2 — Test-Server auf test.schmidtundtoechter.com (development)

- Ein Pull Request von `feature/*` oder `fix/*` nach **`development`** wird geöffnet.
- Mindestens ein weiteres Teammitglied reviewed den PR.
- CI-Checks (Lint, Syntax, Skript-Validierung) müssen grün sein.
- Nach Approval: Squash-Merge in `development`.

### Stage 3 — Staging Server beim Kunden (staging = Pre-Production)

- Für den Release-Kandidaten wird ein PR von `development` nach `staging` geöffnet und gemergt.
- `staging` wird auf einem dedizierten Acceptance-System deployt (z. B. ein Testmandant / Bench).
- Funktionaler Smoke-Test: Kann ERPNext gestartet werden? Sind alle Apps installiert?
- Gefundene Fehler werden als `fix/*`-Branch von `development` erstellt und über `development` erneut nach `staging` gebracht — kein direktes Pushen auf `staging`.
- Ist der Acceptance-Test bestanden, wird ein PR von `staging` nach `main` geöffnet.

### Stage 4 — Production (main)

- PR von `staging` nach `main` wird reviewt (mindestens Lead Developer).
- Nach Merge auf `main`: Release-Tag wird gesetzt (siehe [Release-Prozess](Release-Prozess.md)).
- Deployment auf Produktionssystemen erfolgt aus `main` (manuell ausgelöst oder via CI/CD-Hook).
- Nach dem Deployment: kurzer Verifikations-Check (Service-Status, Logs).

---

## Hotfix-Prozess

Kritische Produktionsfehler können direkt von `main` abgezweigt werden:

```
main
 └── hotfix/<name>
```

1. Branch `hotfix/<name>` von `main` erstellen.
2. Fix entwickeln und committen.
3. PR nach `main` öffnen (dringend, vereinfachtes Review).
4. Nach Merge: Patch-Release-Tag setzen.
5. `main` zurück in `staging` mergen, um Divergenz zu vermeiden.

---

## Deployment-Checkliste

- [ ] CI-Checks auf dem Quell-Branch sind grün
- [ ] PR reviewed und approved
- [ ] Staging-Deployment erfolgreich getestet
- [ ] Release-Tag gesetzt (bei Merge auf `main`)
- [ ] Deployment auf Produktion ausgelöst
- [ ] Post-Deployment-Verifikation durchgeführt

---

*Zuletzt aktualisiert: April 2026*
