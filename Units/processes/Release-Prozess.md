# Release-Prozess

Jeder Merge auf `main` entspricht einem neuen Release. Releases werden mit Git-Tags nach SemVer versioniert.

---

## Versionierungsstrategie (SemVer)

Wir folgen [Semantic Versioning 2.0.0](https://semver.org/):

| Typ | Schema | Wann? |
|---|---|---|
| **MAJOR** | `X.0.0` | Breaking Changes: Infrastruktur-Umbauten, geänderte Konfigurationsformate, Migrationsbedarf |
| **MINOR** | `0.Y.0` | Neue Features, neue Apps, Architekturverbesserungen (rückwärtskompatibel) |
| **PATCH** | `0.0.Z` | Bugfixes, Tippfehler, kleine Korrekturen |

### Entscheidungshilfe

```
Müssen bestehende Installationen manuell angepasst werden?
  Ja → MAJOR

Wird neue Funktionalität hinzugefügt (ohne Migrationsaufwand)?
  Ja → MINOR

Nur ein Fehler behoben?
  Ja → PATCH
```

---

## Release-Prozess Schritt für Schritt

### 1. Pre-Release-Checks

- [ ] Alle CI-Checks auf `main` sind grün
- [ ] PR wurde reviewt
- [ ] Keine offenen, kritischen Issues
- [ ] CHANGELOG wurde im PR aktualisiert

### 2. Versionsnummer bestimmen

Die neue Versionsnummer wird basierend auf den Änderungen des Merges festgelegt (siehe Tabelle oben). Im Zweifel konservativ vorgehen: lieber MINOR als PATCH, lieber MAJOR als MINOR.

### 3. CHANGELOG aktualisieren

Format in `CHANGELOG.md`:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Breaking Changes (nur bei MAJOR)
- ...
- Migrations-Anleitung: ...
```

### 4. Git-Operationen

[ ] Überarbeiten !!!

```bash
# Auf development arbeiten
git checkout development
git pull origin development

# Tag setzen
git tag vX.Y.Z -m "Release vX.Y.Z: <kurze Zusammenfassung>"

# Tag pushen
git push origin vX.Y.Z
```

Commit-Message-Format für den Merge-Commit (wird beim PR-Merge gesetzt):

```
Release vX.Y.Z: <kurze Zusammenfassung>
```

### 5. Release auf GitHub/Gitea

Ein Release-Eintrag wird aus dem Tag erstellt:

- **Titel**: `vX.Y.Z — <kurzer Titel>`
- **Body**: Inhalt aus dem CHANGELOG für diese Version
- Bei MAJOR: Migrations-Anleitung als eigener Abschnitt

### 6. Post-Release

- [ ] Tag ist auf Remote gepusht und sichtbar
- [ ] Release-Eintrag ist angelegt
- [ ] Staging wird mit `main` synchronisiert: `git merge main` auf `staging`

---

## Regeln & Konventionen

- **Kein Force-Push auf `main` oder auf Tags.**
- Tags sind immutable — ein einmal gesetzter Tag wird nicht verschoben oder gelöscht.
- PATCH-Releases benötigen keinen ausführlichen Release-Eintrag; ein Tag mit kurzer Beschreibung genügt.
- MAJOR-Releases erfordern immer eine Migrations-Anleitung.

---

## Versionshistorie (Beispiel)

| Version | Datum | Typ | Beschreibung |
|---|---|---|---|
| `v1.0.0` | 2025-01-15 | MAJOR | Initiales stabiles Release |
| `v1.1.0` | 2025-03-10 | MINOR | Raven und DATEV-Export hinzugefügt |
| `v1.1.1` | 2025-03-22 | PATCH | Fix: SSH-Key-Pfad in deploy.sh |

---

*Zuletzt aktualisiert: April 2026*
