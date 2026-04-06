# Gemeinsames Systemmodell für Namer und StashApp auf Proxmox

## Ziel

Eine gemeinsame, wiederverwendbare Architektur für beide Anwendungen:

- **Namer**
- **StashApp**

## Grundidee

Nicht beide Apps sofort in einen einzigen Container packen, sondern zuerst ein einheitliches Betriebsmodell schaffen.

## Empfohlenes Betriebsmodell

### Ebene 1: NAS-Anbindung

Die QNAP-Freigaben werden auf dem **Proxmox-Host** gemountet, bevorzugt per NFS.

Beispiel:

```text
/mnt/bindmounts/qnap-namer
/mnt/bindmounts/qnap-stash
```

### Ebene 2: LXC pro Anwendung

Jede Anwendung bekommt zunächst ihren **eigenen unprivilegierten Docker-LXC**.

Beispiel:

- `namer` LXC
- `stashapp` LXC

### Ebene 3: Docker pro Anwendung

Im jeweiligen LXC läuft Docker, und die Anwendung selbst läuft als Container.

### Ebene 4: standalone Installer im LXC

Jede App bekommt ein **eigenes standalone Installationsskript**, das direkt im Container nutzbar ist.

## Vorteile

- gleiche Denke für beide Projekte
- gleiche Mount-Logik
- gleiche Docker-Logik
- gleiche Update-Strategie
- einfache Fehlersuche
- spätere Konsolidierung leichter möglich

## Warum nicht sofort alles in einen Container

Für den Anfang ist Trennung sinnvoll:

- Namer ist ein Watchdog-/Rename-Workflow
- StashApp ist Bibliothek, Weboberfläche und Metadatenverwaltung
- Fehler und Rechteprobleme lassen sich getrennt leichter testen

## Späterer Ausbauschritt

Wenn beide Setups stabil laufen, kann man prüfen:

- gemeinsamer Verwaltungscontainer
- gemeinsame Proxmox-Erstellerskripte
- gemeinsames Meta-Repository
- ein zentrales Setup-Framework für mehrere Apps

## Kurzfassung

Der richtige erste Schritt ist **nicht** sofort eine gemeinsame App, sondern zuerst eine **gemeinsame Systemarchitektur**.

Diese Architektur lautet:

```text
QNAP NAS -> Proxmox Host Mount -> eigener Docker-LXC pro App -> standalone Installer im LXC -> Docker-Container der App
```
