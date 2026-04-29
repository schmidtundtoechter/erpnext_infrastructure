# Development-Prozess

Arbeitsablauf für die Feature-Entwicklung mit Trello als Task-Board.

---

## Überblick

```
Trello (Backlog / Planung)
       ↓
  Feature-Branch
       ↓
   Pull Request → Code Review
       ↓
  Merge in staging
       ↓
  Release (via main)
```

---

## Trello-Board-Struktur

Das Trello-Board spiegelt den Entwicklungsfluss wider:

| Spalte | Bedeutung |
|---|---|
| **Backlog** | Ideen, Anforderungen, ungeklärte Tasks |
| **Refined** | Klar definierte Tasks, bereit zur Bearbeitung |
| **In Progress** | Wird aktiv entwickelt (Assignee gesetzt) |
| **In Review** | PR ist offen, wartet auf Review |
| **Done** | Gemergt und deployed |

### Karten-Konvention

Jede Trello-Karte enthält:

- **Titel**: Kurze, aktive Beschreibung (`ERPNext-Bench für Mandant X einrichten`)
- **Beschreibung**: Ziel, Kontext, Akzeptanzkriterien
- **Label**: `feature`, `fix`, `chore`, `docs` o. Ä.
- **Assignee**: Die Person, die den Task bearbeitet
- **Branch-Name** (in der Karte notiert): z. B. `feature/bench-mandant-x`

---

## Entwicklungsablauf

### 1. Task aus Trello aufnehmen

- Karte aus **Refined** nehmen und auf **In Progress** schieben.
- Assignee auf sich selbst setzen.
- Branch-Namen in der Karte notieren.

### 2. Feature-Branch erstellen

```bash
git checkout staging
git pull origin staging
git checkout -b feature/<kurzer-name>
```

Branch-Namenskonventionen:
- `feature/<name>` — neue Funktionalität
- `fix/<name>` — Fehlerbehebung
- `chore/<name>` — Wartungsaufgaben (Updates, Aufräumen)
- `docs/<name>` — reine Dokumentationsänderungen

### 3. Entwickeln & Committen

- Commits sind klein und fokussiert — ein Commit, eine logische Änderung.
- Commit-Message-Format: `<type>: <kurze Beschreibung>`
  - `feat: add bench setup for customer X`
  - `fix: correct docker-compose volume path`
  - `chore: update ERPNext version to 15.x`
  - `docs: document SSH key setup`
- Keine WIP-Commits auf den Branch pushen, die CI kaputt machen.

### 4. Pull Request öffnen

- PR-Titel entspricht der Trello-Karten-Beschreibung.
- PR-Body enthält:
  - **Was** wurde geändert?
  - **Warum** (Link zur Trello-Karte)?
  - **Wie testen?** (kurze Test-Anleitung oder Hinweis "keine manuelle Aktion nötig")
- Trello-Karte auf **In Review** schieben.
- Mindestens einen Reviewer assignen.

### 5. Code Review

- Reviewer schaut auf: Korrektheit, Sicherheit, Einhaltung von Konventionen, fehlende Tests.
- Feedback wird als Kommentar im PR gegeben.
- Änderungen werden im selben Branch gepusht — kein Force-Push nach Review-Beginn.
- Bei Approval: Squash-Merge in `staging` durch den Autor oder Lead Developer.

### 6. Nach dem Merge

- Trello-Karte auf **Done** schieben.
- Feature-Branch löschen: `git push origin --delete feature/<name>`
- Lokalen Branch aufräumen: `git branch -d feature/<name>`

---

## Qualitätssicherung

### Vor dem PR

- [ ] Skripte lokal getestet
- [ ] Keine Credentials oder Keys committed
- [ ] Keine temporären Debug-Ausgaben im Code
- [ ] Dokumentation bei Bedarf aktualisiert

### Im Review

- Mindestens 1 Approval erforderlich
- CI muss grün sein
- Bei strukturellen Änderungen: Lead Developer als Reviewer

---

## Kommunikation

- Fragen zu einem Task werden direkt in der **Trello-Karte** als Kommentar gestellt — nicht per Chat, damit der Kontext erhalten bleibt.
- Blockers werden sofort in der Karte vermerkt und im Team kommuniziert.
- Karten, die länger als 1 Woche in **In Progress** stehen, werden im nächsten Sync besprochen.

---

## Sync-Rhythmus

| Meeting | Rhythmus | Inhalt |
|---|---|---|
| Kurzer Sync | wöchentlich | Blockers, In-Progress-Status, Priorisierung |
| Backlog Refinement | bei Bedarf | Neue Karten definieren, Tasks schärfen |
| Retrospektive | monatlich | Prozessverbesserungen |

---

*Zuletzt aktualisiert: April 2026*
