# MyFTPClient

macOS-SwiftUI-Projekt für einen einfachen SFTP-Client mit fest hinterlegten Verbindungsdaten in der `Info.plist`.

Die App bietet:

- eine Startansicht mit den Verbindungsdaten und den Buttons `Diagnose` und `Verbinden`
- einen zweigeteilten Datei-Explorer
- links lokale Dateien vom `Desktop`
- rechts die Dateien auf dem SFTP-Server
- Upload vom Desktop zum Server
- Download vom Server zum Desktop
- Navigation in beiden Verzeichnisansichten

## Projektstatus

Der aktuelle Stand ist funktionsfähig für den vorgesehenen Anwendungsfall:

- Verbindung zu `ssh.strato.de` per SFTP
- Anzeige der Remote-Dateien
- Upload
- Download
- Navigation im lokalen Desktop
- Navigation in Remote-Verzeichnissen

Der lokale Bereich ist absichtlich auf den `Desktop` reduziert. `Documents` wurde wieder entfernt, weil der zusätzliche macOS-Berechtigungspfad in dieser App unnötige Komplexität erzeugt hat.

## Voraussetzungen

- macOS
- Xcode 26 oder kompatibel
- CocoaPods
- FileZilla ist auf dem System installiert

Wichtig:

- Die App verwendet aktuell den macOS-Systemweg über `sftp` und `expect`.
- Das Projekt enthält zusätzlich eine CocoaPods-Integration mit `NMSSH`, weil dieser Weg während der Fehlersuche ausprobiert wurde.
- Gebaut und getestet wird das Projekt derzeit über die Workspace-Datei.

## Projektstruktur

- [`MyFTPClient.xcworkspace`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient.xcworkspace)
  Der Einstiegspunkt zum Öffnen des Projekts in Xcode.
- [`MyFTPClient.xcodeproj`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient.xcodeproj)
  Das eigentliche Xcode-Projekt.
- [`Podfile`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/Podfile)
  CocoaPods-Konfiguration.
- [`MyFTPClient/MyFTPClientApp.swift`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/MyFTPClientApp.swift)
  App-Einstieg.
- [`MyFTPClient/ContentView.swift`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/ContentView.swift)
  UI für Verbindungsansicht und Datei-Explorer.
- [`MyFTPClient/FTPClientViewModel.swift`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/FTPClientViewModel.swift)
  UI-Status, lokale Navigation, Auswahl und Transfersteuerung.
- [`MyFTPClient/SFTPService.swift`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/SFTPService.swift)
  Verbindung, Remote-Listing und Dateiübertragung über den SFTP-Transport.
- [`MyFTPClient/Models.swift`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/Models.swift)
  Modelle und Konfigurationsstruktur.
- [`MyFTPClient/Info.plist`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient/Info.plist)
  Feste Verbindungsdaten und App-Konfiguration.

## Konfiguration

Die Verbindungsdaten werden aus der `Info.plist` gelesen.

Verwendete Schlüssel:

- `FTPServer`
- `FTPType`
- `FTPPort`
- `FTPUsername`
- `FTPPassword`
- `FTPPrivateKeyPath`

Beispiel:

```xml
<key>FTPServer</key>
<string>ssh.strato.de</string>
<key>FTPType</key>
<string>sftp</string>
<key>FTPPort</key>
<integer>22</integer>
<key>FTPUsername</key>
<string>...</string>
<key>FTPPassword</key>
<string>...</string>
<key>FTPPrivateKeyPath</key>
<string></string>
```

Hinweise:

- Die App liest diese Werte direkt aus dem Bundle.
- Änderungen an der `Info.plist` werden erst nach einem neuen Build in der App wirksam.
- Das Passwort liegt bewusst im Klartext in der `Info.plist`, weil genau dieser Projektmodus angefordert war.

## Projekt öffnen

Nicht die `.xcodeproj` direkt öffnen, sondern:

- [`MyFTPClient.xcworkspace`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/MyFTPClient.xcworkspace)

Grund:

- Die Workspace-Datei bindet die CocoaPods-Struktur korrekt ein.

## Build

Verwendeter Build-Befehl:

```sh
xcodebuild -workspace MyFTPClient.xcworkspace -scheme MyFTPClient -configuration Debug -derivedDataPath ./DerivedData -arch x86_64 CODE_SIGNING_ALLOWED=NO build
```

Wichtige Punkte:

- Es wird aktuell mit `-arch x86_64` gebaut.
- Das Projekt wurde in diesem Zustand erfolgreich auf diesem Weg gebaut.
- Das erzeugte App-Bundle liegt anschließend unter:

```text
DerivedData/Build/Products/Debug/MyFTPClient.app
```

## App verwenden

### 1. Verbindung

Beim Start zeigt die App:

- Server
- Typ
- Port
- Benutzer
- maskiertes Passwort
- Authentifizierungstyp

Buttons:

- `Diagnose`
  Prüft die Verbindung und Anmeldung.
- `Verbinden`
  Baut die Verbindung auf und öffnet danach den Datei-Explorer.

### 2. Lokale Ansicht

Die linke Seite zeigt den Desktop.

Bedienung:

- Einfacher Klick auf eine Datei markiert oder entmarkiert sie für den Transfer.
- Doppelklick auf einen Ordner öffnet ihn.
- `Hoch` geht eine Ebene zurück.
- `Aktualisieren` lädt die aktuelle Ansicht neu.

Wichtig:

- Nur Dateien sind auswählbar.
- Ordner zeigen keinen Auswahl-Kreis und werden nicht für Transfers markiert.

### 3. Server-Ansicht

Die rechte Seite zeigt das aktuelle Verzeichnis auf dem SFTP-Server.

Bedienung:

- Einfacher Klick auf eine Datei markiert oder entmarkiert sie für den Download.
- Doppelklick auf einen Ordner öffnet ihn.
- `Hoch` geht zum übergeordneten Remote-Ordner.
- `Aktualisieren` lädt das Remote-Verzeichnis neu.

### 4. Übertragen

Der Hauptbutton oben passt sich an:

- `Hochladen`, wenn nur lokal Dateien markiert sind
- `Herunterladen`, wenn nur remote Dateien markiert sind
- `Übertragen`, wenn noch keine oder uneindeutige Auswahl vorliegt

Regeln:

- Pro Aktion ist nur eine Richtung erlaubt.
- Sind auf beiden Seiten gleichzeitig Dateien markiert, erscheint eine Fehlermeldung.

## Auswahlverhalten

Die Dateiauswahl verwendet absichtlich keine native `List(selection:)`-Mehrfachauswahl mehr.

Stattdessen:

- jede Datei hat ihren eigenen Auswahlzustand
- Auswahl per einfachem Klick
- visuelle Markierung mit Kreis und Hintergrund

Grund:

- Das war im laufenden Betrieb robuster als die vorherige macOS-Listen-Selektion, die nach Transfers inkonsistent werden konnte.

## Technische Umsetzung

### UI

Die UI ist vollständig in SwiftUI aufgebaut.

Wichtige Views:

- `RootView`
- `ConnectionView`
- `FileExplorerView`
- `LocalPaneView`
- `RemotePaneView`
- `FileRow`

### Zustand

Das `FTPClientViewModel` verwaltet:

- Verbindungsstatus
- Status- und Fehlermeldungen
- lokales aktuelles Verzeichnis
- aktuelles Remote-Verzeichnis
- ausgewählte lokale Dateien
- ausgewählte Remote-Dateien

### Remote-Zugriff

`SFTPService` übernimmt:

- Verbindungstest
- Remote-Listing
- Upload
- Download

Der aktuelle Transport basiert auf:

- `sftp`
- `expect`

Dabei werden SFTP-Kommandos wie `pwd`, `ls -la`, `put` und `get` an den interaktiven SFTP-Prozess übergeben.

## Warum dieser Transportweg?

Während der Entwicklung wurden mehrere Wege ausprobiert:

- `Citadel`
- `swift-nio-ssh`
- `NMSSH`
- `fzsftp`
- `psftp`
- OpenSSH-Systemtools

Die Fehlersuche war notwendig, weil sich das Zielsystem gegenüber verschiedenen SSH/SFTP-Stacks unterschiedlich verhalten hat.

Wichtige Erkenntnis:

- Der zunächst in der App hinterlegte Passwortwert war nicht identisch mit dem funktionierenden FileZilla-Wert.
- Nach Korrektur des Passworts war die Verbindung möglich.

## Bekannte Einschränkungen

- Lokaler Dateibereich ist nur der Desktop.
- Das Passwort liegt in der `Info.plist` und damit nicht sicher.
- Der SFTP-Zugriff basiert auf externen Systemtools statt auf einer vollständig nativen Swift-Bibliothek.
- Das Projekt wird aktuell über die Workspace-Datei und mit `x86_64` gebaut.
- Die CocoaPods-/`NMSSH`-Spuren sind noch im Projekt vorhanden, obwohl der aktive Transport derzeit `sftp`/`expect` ist.

## Fehlerbilder und Hinweise

### Änderungen an der `Info.plist` greifen nicht

Dann wurde die App vermutlich nicht neu gebaut.

Abhilfe:

- Projekt neu bauen
- App neu starten

### Verbindung schlägt fehl

Prüfen:

- Stimmt der Wert in `FTPPassword` wirklich?
- Wurde die App nach Änderungen neu gebaut?
- Wird die Workspace-Datei geöffnet?

### Remote-Download oder Upload klappt nicht

Dann die Fehlermeldung aus dem App-Dialog lesen. Die App gibt die vom Transport gesammelte Ausgabe relativ direkt weiter.

## Aufräumoptionen für später

Falls das Projekt weiter gepflegt wird, wären die nächsten sauberen Schritte:

- ungenutzte `NMSSH`-/Pod-Reste entfernen
- Transport auf eine einzige, klar unterstützte Bibliothek oder auf einen vollständig gekapselten Systemtool-Weg vereinheitlichen
- Passwörter aus der `Info.plist` entfernen
- lokale Dateibereiche konfigurierbar machen
- Fortschrittsanzeige für große Transfers ergänzen

## Lizenz / Hinweise

Für die im Projekt eingebundenen externen Komponenten gelten deren jeweilige Lizenzen, insbesondere über CocoaPods unter:

- [`Pods`](/Users/peterpetermann/Desktop/Codex/MyFTPClient/Pods)

Die App selbst ist aktuell ein projektspezifischer Prototyp mit fest eingebetteter Zielkonfiguration.
