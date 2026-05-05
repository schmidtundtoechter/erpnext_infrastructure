# Release-Prozess

Jede Lieferung an den Kunden (Merge auf `staging`) ist ein Release und erhält eine neue Versionsnummer. Merges auf `main` bestätigen das Release als Produktionsstand. Merges auf `development` können optional bereits eine Vorversion erhalten.

---

## Wann wird ein Release erstellt?

| Merge-Ziel      | Release-Pflicht | Versions-Suffix | Bedeutung                                      |
|:----------------|:----------------|:----------------|:-----------------------------------------------|
| `development`   | Optional        | `-dev`          | Interne Vorabversion für Teamtests             |
| `staging`       | **Pflicht**     | keiner          | Release-Kandidat, Lieferung zur Kundenabnahme  |
| `main`          | **Pflicht**     | keiner          | Finales Produktions-Release (gleiche Version)  |

**Grundregel:** Jede Lieferung an den Kunden ist ein eigenes Release. Bevor ein PR von `development` nach `staging` geöffnet wird, muss die Versionsnummer erhöht und der CHANGELOG aktualisiert sein.

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

Im Zweifel konservativ vorgehen: lieber MINOR als PATCH, lieber MAJOR als MINOR.

---

## Release-Prozess Schritt für Schritt

### Beim Merge in `development` (optional)

Ein Vorab-Tag kann gesetzt werden, wenn der Stand intern als testbar gilt. Das ist kein formales Kundenrelease.

- [ ] Versionsnummer bestimmen (z. B. `v1.2.0-dev`)
- [ ] CHANGELOG mit `[Unreleased]`-Eintrag oder Dev-Eintrag aktualisieren
- [ ] Tag setzen und pushen:

```bash
git tag v1.2.0-dev -m "Dev-Stand: <kurze Zusammenfassung>"
git push origin v1.2.0-dev
```

---

### Beim PR nach `staging` (Pflicht)

Dieser Schritt erzeugt das formale Release für die Kundenabnahme. Die Versionsnummer wird **vor dem PR** auf `development` gesetzt.

#### 1. Versionsnummer bestimmen

Basierend auf den Änderungen seit dem letzten Release die neue Version festlegen (siehe SemVer-Tabelle oben).

#### 2. CHANGELOG aktualisieren

In `CHANGELOG.md` einen neuen Abschnitt anlegen:

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

#### 3. Tag auf `development` setzen

```bash
git checkout development
git pull origin development

# Tag setzen
git tag vX.Y.Z -m "Release vX.Y.Z: <kurze Zusammenfassung>"

# Tag pushen
git push origin vX.Y.Z
```

#### 4. PR von `development` nach `staging` öffnen

- **PR-Titel**: `Release vX.Y.Z: <kurzer Titel>`
- **PR-Body**: Inhalt des CHANGELOG-Eintrags für diese Version

#### 5. Release-Eintrag auf GitHub/Gitea anlegen

Nach dem Merge auf `staging` wird ein Release-Eintrag aus dem Tag erstellt:

- **Titel**: `vX.Y.Z — <kurzer Titel>`
- **Body**: Inhalt aus dem CHANGELOG für diese Version
- Bei MAJOR: Migrations-Anleitung als eigener Abschnitt

---

### Beim PR nach `main` (Pflicht)

Kein neuer Tag — die Version wurde bereits beim Staging-Release gesetzt. Der Merge auf `main` bestätigt denselben Stand als Produktionsrelease.

- [ ] Kundenabnahme auf Staging-Server liegt vor
- [ ] Alle Integrationstests sind grün
- [ ] PR reviewed und approved (Lead Developer)
- [ ] Nach Merge: automatisches Produktions-Deployment abwarten
- [ ] Post-Deployment-Verifikation durchführen (Service-Status, Logs, Erreichbarkeit)
- [ ] Sicherstellen, dass `staging` und `development` mit `main` synchron sind (ggf. `main` zurückmergen)

---

## Pre-Release-Checks (vor jedem Staging-PR)

- [ ] Versionsnummer erhöht (SemVer)
- [ ] CHANGELOG aktualisiert und committed
- [ ] Git-Tag gesetzt und gepusht
- [ ] CI-Checks auf `development` sind grün
- [ ] PR reviewed und approved durch Teammitglied

---

## Regeln & Konventionen

- **Kein Force-Push auf `main`, `staging` oder auf Tags.**
- Tags sind immutable — ein einmal gesetzter Tag wird nicht verschoben oder gelöscht.
- PATCH-Releases benötigen keinen ausführlichen Release-Eintrag; ein Tag mit kurzer Beschreibung genügt.
- MAJOR-Releases erfordern immer eine Migrations-Anleitung im CHANGELOG und im Release-Eintrag.
- Die Versionsnummer wird immer auf `development` gesetzt, nie direkt auf `staging` oder `main`.

---

## Versionshistorie (Beispiel)

| Version | Datum | Typ | Beschreibung |
|---|---|---|---|
| `v1.0.0` | 2025-01-15 | MAJOR | Initiales stabiles Release |
| `v1.1.0` | 2025-03-10 | MINOR | Raven und DATEV-Export hinzugefügt |
| `v1.1.1` | 2025-03-22 | PATCH | Fix: SSH-Key-Pfad in deploy.sh |

---

*Zuletzt aktualisiert: Mai 2026*
