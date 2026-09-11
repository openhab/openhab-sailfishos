# NFC-Tags in harbour-openhab (Sailfish OS)

Recherche- und Anforderungsdokument zur Übernahme des NFC-Features aus der openHAB-Android-App.

Stand: 07.09.2026 (Gerätebefunde vom Fairphone 4 eingearbeitet, siehe Abschnitt G; davor: Review nach Flow-Festlegung, Entscheidungen in §7 und im Abschnitt „Openhab FLOW")
Bezug: https://github.com/openhab/openhab-sailfishos, https://github.com/openhab/openhab-android

---

## 1. Ziel

Ein NFC-Tag soll mit einer openHAB-Aktion verknüpft werden (z. B. Item `Licht_Wohnzimmer`, Command `ON`). Beim Auflegen des Tags sendet die App den Command per REST an den openHAB-Server. Zusätzlich soll die App Tags selbst beschreiben können.

Die Tag-Inhalte müssen **binärkompatibel zur Android-App** sein — ein in der Android-App geschriebener Tag muss auf Sailfish funktionieren und umgekehrt.

---

## 2. Wie das Android-Feature funktioniert

Quelle: `openhab-android`, `model/NfcTag.kt`, `ui/WriteTagActivity.kt`, `background/NfcReceiveActivity.kt`, `AndroidManifest.xml`.

### 2.1 Tag-Inhalt

Ein einzelner **NDEF-URI-Record** (TNF = Well-Known, Type = `U`) mit eigenem Schema:

| Zweck | URI |
|---|---|
| Item-Command | `openhab://?i=<item>&s=<state>[&l=<label>][&m=<mappedState>][&d=true]` |
| Sitemap öffnen | `openhab:///<sitemap-pfad>` (Pfad hinter `/rest/sitemaps`) |

Query-Parameter:

| Param | Bedeutung | Hinweis |
|---|---|---|
| `i` | Item-Name | Alt-Alias: `item` (deprecated, wird weiter gelesen) |
| `s` | zu sendender Command/State | Alt-Alias: `command` (deprecated) |
| `l` | Item-Label | nur für UI/Feedback |
| `m` | gemappter Anzeige-State | nur für UI/Feedback |
| `d` | Device-ID-Modus | dann ist `s` = `UNSUPPORTED` |

Die Android-App baut zwei Varianten: eine **lange URI** (mit `l`/`m`) und eine **kurze URI** (nur `i`/`s`). Passt die lange nicht in den Tag-Speicher, wird die kurze geschrieben. Beim Lesen sind alle Felder außer `i`/`s` optional.

### 2.2 Verhalten beim Auflegen

Android registriert einen `NDEF_DISCOVERED`-Intent-Filter auf `scheme="openhab"`. Die `NfcReceiveActivity` läuft ohne UI, übergibt den Command an den `BackgroundTasksManager` (Queue mit Retry) und startet nur bei Sitemap-Tags die MainActivity. **Die App muss dafür nicht laufen.**

---

## 3. NFC-Stack unter Sailfish OS

### 3.1 nfcd

NFC-Hardwarezugriff läuft ausschließlich über **`nfcd`** (https://github.com/sailfishos/nfcd), einen Systemdienst, der den Zugriff arbitriert und D-Bus-Schnittstellen auf dem **System-Bus** anbietet. Es gibt keine Qt/QML-NFC-API von Jolla — kein QtNfc, kein `nemo-qml-plugin-nfc`. Der Zugriff erfolgt direkt über D-Bus.

Unterstützt: Reader/Writer (ISO-DEP/Type 4 und Type 2), Peer-to-Peer (NFC-DEP), Card Emulation.

**Service:** `org.sailfishos.nfc.daemon`, Root-Objektpfad `/`, Adapter darunter (z. B. `/nfc0`).

### 3.2 Relevante Interfaces

| Interface | Für uns relevante Members |
|---|---|
| `org.sailfishos.nfc.Daemon` (an `/`) | `GetAll6() → (i version, ao adapters, i daemon_version, u mode, u techs, b blocked)`, `GetAdapters() → ao`, Signal `AdaptersChanged(ao)`, `RequestMode(u enable, u disable) → u id` / `ReleaseMode(u id)` |
| `org.sailfishos.nfc.Adapter` (an `/nfc0`) | `GetAll4()`, `GetTags() → ao`, Signal **`TagsChanged(ao)`**, `GetEnabled/GetPowered/GetMode`, Signale `EnabledChanged`, `PoweredChanged` |
| `org.sailfishos.nfc.Tag` | `GetAll3() → (…, u type, as interfaces, ao ndef_records, a{sv} poll_parameters)`, `GetNdefRecords() → ao`, `Acquire2(b wait)` / `Release2()`, `Deactivate()`, `Transceive(ay) → ay`, Signal `Removed()` |
| `org.sailfishos.nfc.NDEF` | `GetAll() → (i version, u flags, u tnf, as interfaces, ay type, ay id, ay payload)`, `GetPayload() → ay`, `GetRawData() → ay` |
| `org.sailfishos.nfc.TagType2` | `GetAll() → (i, u block_size, u data_size, ay serial)`, `ReadAllData() → ay`, **`WriteData(u offset, ay data) → u written`**, `Read/Write(sector, block, …)` |
| `org.sailfishos.nfc.Settings` (Service `org.sailfishos.nfc.settings`) | `GetEnabled() → b`, `SetEnabled(b)`, Signal `EnabledChanged(b)` |

Standard-Modus von nfcd ist `NFC_MODE_READER_WRITER` (0x02), d. h. Polling läuft ohne Zutun der App, sofern NFC in den Systemeinstellungen aktiv ist. Auf dem Testgerät bestätigt (`Adapter.GetMode = 2`, siehe Abschnitt G).

> **Achtung, Tabelle oben ist optimistisch.** Auf dem Testgerät (Sailfish 5.0.0.72) meldet das `Daemon`-Interface **Version 4**, `Tag` meldet **5**, `NDEF` und `TagType2` jeweils **1**. `GetAll6` existiert dort also **nicht** — wer dagegen programmiert, bekommt `UnknownMethod`. Konkrete Zahlen und Rohantworten in Abschnitt G; die daraus folgende Marschrichtung steht in B-10 (Einzelmethoden statt `GetAllN`).

### 3.3 Wichtige Plattform-Constraints

- **Display aus = NFC aus.** Das nfcd-`settings`-Plugin fährt den NFC-Chip bei ausgeschaltetem Display herunter. Tag-Erkennung funktioniert nur bei eingeschaltetem Bildschirm (in der Praxis ähnlich wie Android).
- **Schreiben nur für Type-2-Tags** über die D-Bus-API (`TagType2.WriteData`). Das deckt NTAG213/215/216 und Mifare Ultralight ab — also die üblichen Sticker. Type-4 ließe sich nur über rohe APDUs via `Tag.Transceive` beschreiben (aufwendig, out of scope).
- **Nicht jedes Gerät hat NFC** (z. B. Xperia X nicht, XA2/10/10 II/10 III ja). Zur Laufzeit über `GetAdapters()` prüfen und Feature ausblenden, wenn leer.
- **NFC ist AppSupport-seitig deaktiviert** — die Android-openHAB-App unter Sailfish kann NFC nicht nutzen. Das native Feature ist also nicht redundant.
- Kommandozeilen-Tools zum Gegentesten: Paket `nfcd-tools` (`ndef-read`, `ndef-write`, `nfc-io`, `iso-dep`).

---

## 4. Sailjail / Harbour

### 4.1 Die NFC-Permission existiert und ist Harbour-tauglich

`NFC` steht in `sailjail-permissions` und ist in der Harbour-Validator-Whitelist (`allowed_permissions.conf`). Nötige Änderung in `harbour-openhab.desktop`:

```ini
[X-Sailjail]
OrganizationName=org.openhab
ApplicationName=harbour-openhab
Permissions=Internet;NFC
```

`NFC.permission` gewährt genau:

```
dbus-system.talk      org.sailfishos.nfc.daemon
dbus-system.call      org.sailfishos.nfc.daemon=org.sailfishos.nfc.*@/*
dbus-system.broadcast org.sailfishos.nfc.daemon=org.sailfishos.nfc.*@/*
dbus-system.talk      org.sailfishos.nfc.settings
dbus-system.call      org.sailfishos.nfc.settings=org.sailfishos.nfc.*@/*
dbus-system.broadcast org.sailfishos.nfc.settings=org.sailfishos.nfc.*@/*
dbus-system.talk      org.neard
dbus-system.call      org.neard=org.neard.*@/*
dbus-system.broadcast org.neard=org.neard.*@/*
```

Damit sind Aufrufe **und** Signalempfang für Daemon/Adapter/Tag/NDEF/TagType2/Settings abgedeckt. Kein `dbus-system.own` — die App kann keinen Namen auf dem System-Bus besitzen (siehe 4.3).

**✅ Verifiziert am 07.09.2026 im SDK-Target `SailfishOS-4.5.0.18-aarch64`** (`sfdk tools target exec … cat /etc/sailjail/permissions/NFC.permission`): Die Datei existiert dort bereits und enthält wortgleich die oben aufgeführten Regeln. Damit ist belegt, dass **die in O-5 gesetzte Untergrenze Sailfish 4.5 tatsächlich trägt** — die NFC-Permission war die einzige Zutat, bei der das offen war. Nebenbefund: `org.sailfishos.system_nfc` steht **nicht** in der Permission (die Datei trägt dazu selbst ein `FIXME`), unsere App kann den System-Handler also weder ansprechen noch stören — für O-1 beruhigend.

### 4.2 Erlaubte APIs für den D-Bus-Zugriff

- QML: `import Nemo.DBus 2.0` ist in `allowed_qmlimports.conf`, `nemo-qml-plugin-dbus-qt5` in `allowed_requires.conf`.
- C++: `libQt5DBus.so.5` ist in `allowed_libraries.conf`.

Beide Wege sind Harbour-konform. **Empfehlung: C++.** Byte-Arrays (`ay`) für NDEF-Payload und TLV-Block sind über Nemo.DBus fummelig; die App hat mit `src/ssemanager.cpp` bereits eine C++-Schicht, in die sich ein `NfcManager` sauber einfügt (`QDBusConnection::systemBus()`, Signal `TagsChanged` per `connect`, ein QML-Singleton/Context-Property nach oben).

### 4.3 Kernproblem: kein Auto-Start bei Tag-Kontakt

nfcd kann Anwendungen beim Auflegen eines Tags automatisch starten — über das Plugin `dbus_handlers`. Dafür braucht es:

1. eine Konfigurationsdatei in **`/etc/nfcd/ndef-handlers/`** (`[URI-Handler]` mit `Service=`, `Path=`, `Method=`), und
2. einen **System-Bus-Namen** der App plus eine D-Bus-Policy in `/etc/dbus-1/system.d/`.

Beides ist für ein Harbour-RPM ausgeschlossen: Der Validator erlaubt im Paket ausschließlich `/usr/bin/<name>`, `/usr/share/<name>/**`, die `.desktop`-Datei und Icons — alles unter `/etc` führt zu „Installation not allowed in this location“. Zusätzlich vergibt Sailjail kein `dbus-system.own`.

**Konsequenz:** Für die Jolla-Store-Version funktioniert der Tag nur, **während die App im Vordergrund läuft** (entspricht Androids Foreground-Dispatch, nicht dem Auto-Start). Der Auto-Start ließe sich nur über ein zusätzliches, außerhalb von Harbour verteiltes Paket (OpenRepos/Chum) realisieren.

Zur Kenntnis: Es existiert bereits ein System-Handler `/etc/nfcd/ndef-handlers/org.sailfishos.systems_nfc.handleNfcTag.conf` (`[URI-Handler]` → `org.sailfishos.system_nfc`), der URI-Tags entgegennimmt. Ob er `openhab://`-URIs beansprucht oder mit „nicht behandelt“ zurückgibt, ist zu testen (siehe offene Punkte).

---

## 5. Anforderungen

### Funktional

| ID | Anforderung | Prio |
|---|---|---|
| F-1 | Beim Auflegen eines Tags mit `openhab://`-URI, während die App im Vordergrund ist, wird der Command via `POST /rest/items/<item>` gesendet — identisch zur bestehenden `sendCommand()`-Funktion. | Muss |
| F-2 | Unterstützung der Parameter `i`/`s` inklusive der deprecated Aliases `item`/`command`. | Muss |
| F-3 | Sitemap-Tags (`openhab:///<pfad>`) navigieren in die entsprechende SitemapPage. | Soll |
| F-4 | Tags beschreiben: aus dem Sitemap-Widget-Kontext (Long-Press analog Android) Item + Command wählen, Tag auflegen, NDEF-URI-Record schreiben. | Soll |
| F-5 | Long/Short-URI-Fallback beim Schreiben: passt die lange URI nicht in `data_size`, wird die kurze geschrieben. | Soll |
| F-6 | Nutzer-Feedback: „Tag auflegen“-Dialog, Erfolg/Fehler, Item-Label aus `l` im Toast/Notification. | Soll |
| F-7 | Feature wird ausgeblendet, wenn kein NFC-Adapter existiert; Hinweis + Verweis auf Systemeinstellungen, wenn NFC deaktiviert ist (`Settings.GetEnabled`). | Muss |
| F-8 | Bekanntes, unerwartetes oder fremdes Tag-Format wird ignoriert, ohne Command zu senden. | Muss |
| F-9 | Nicht behandelt in v1: `d`-Parameter (Device-ID), Card Emulation, P2P. | — |

### Nicht-funktional / technisch

| ID | Anforderung |
|---|---|
| T-1 | `Permissions=Internet;NFC` in der `.desktop`-Datei. |
| T-2 | Kein neuer Runtime-Require nötig; nfcd ist Systemkomponente. Bei QML-Variante zusätzlich `Requires: nemo-qml-plugin-dbus-qt5`. |
| T-3 | Zugriff nur über D-Bus-System-Bus, keine direkte Hardware-/Kernel-Nutzung. |
| T-4 | **Eine** dauerhaft offene `QDBusConnection::systemBus()` für den gesamten `NfcManager`; beim Lesen **und** Schreiben `Tag.Acquire2(true)` vor und `Release2()` nach dem Vorgang, damit nfcd den Tag nicht zwischen zwei Aufrufen deaktiviert und andere Clients nicht dazwischenfunken. Begründung aus dem Gerätetest: G-4. |
| T-5 | Graceful Degradation auf Geräten ohne NFC bzw. bei nfcd-Versionen ohne `GetAll6` (Fallback auf `GetAll`/`GetAdapters`, Interface-Version prüfen). |
| T-6 | Keine Regression für Harbour: Validator-Lauf (`sfdk build` + rpmvalidator) muss sauber bleiben. |
| T-7 | Tests analog zum bestehenden `tests/`-Setup: URI-Parser und NDEF/TLV-Encoder als reine Unit-Tests ohne Hardware. |

---

## 6. Vorgeschlagene Umsetzung

### 6.1 Lesepfad

```
Daemon.GetAdapters()            → /nfc0
Adapter.TagsChanged(ao)         → /nfc0/tag0
Tag.GetAll3()                   → interfaces enthält "org.sailfishos.nfc.NDEF"? ndef_records: ao
NDEF.GetAll()                   → tnf == 1 (well-known), type == "U"
  payload[0] = URI-Prefix-Code (bei "openhab://" = 0x00, kein Kürzel)
  payload[1..] = UTF-8-URI
→ QUrl parsen, i/s extrahieren, sendCommand()
```

### 6.2 Schreibpfad (Type 2)

```
NDEF-URI-Record bauen: [Header 0xD1][TypeLen 1]["U"][PayloadLen][0x00][URI]
TLV umschließen:       0x03 | Länge (1 Byte, oder 0xFF + 2 Byte) | NDEF | 0xFE
TagType2.GetAll()      → data_size prüfen; passt long? sonst short
Tag.Acquire2(true)
TagType2.ReadAllData() → nur geänderte Bytes schreiben (Diff, wie ndef-write)
TagType2.WriteData(0, data)
Tag.Release2()
```

Referenzimplementierung in `nfcd/tools/ndef-write/ndef-write.c` — **mit einer bewussten Abweichung**: Das Tool überschreibt führende TLVs (Lock Control), wir erhalten sie. Begründung und Algorithmus in **G-8**. `Tag.Acquire2`/`Release2` sind dort ebenfalls nicht enthalten, für uns aber Pflicht (T-4, **G-4**).

### 6.3 Phasen

1. **Spike auf dem Gerät** — Permission setzen, Adapter auflisten, Tag lesen, URI ausgeben. Klärt die meisten offenen Punkte unten.
2. **Lesen + Command senden** (F-1, F-2, F-7, F-8) inkl. UI-Feedback.
3. **Schreiben** (F-4, F-5).
4. **Sitemap-Tags** (F-3).

---

## 7. Offene Punkte

| # | Frage                                                                                                                                                                                                                                                                                   | Wie klären |
|---|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---|
| O-1 | Beansprucht der System-URI-Handler `openhab://`-Tags und zeigt womöglich einen Browser-/Fehlerdialog, während unsere App parallel reagiert?                                                                                                                                             | Tag mit `openhab://?i=X&s=ON` beschreiben, auflegen, `journalctl -f` beobachten. |
| O-2 | Bekommt eine sandboxed App die `TagsChanged`-Signale zuverlässig, oder blockt der Firejail-Filter Broadcasts vom Adapter-Objektpfad? Die Regel lautet `org.sailfishos.nfc.*@/*` und sollte passen — verifizieren.                                                                       | Spike (Phase 1) auf dem Gerät. |
| O-3 | Bleibt die App im Vordergrund aktiv genug, wenn das Display an, die App aber verdeckt ist (Cover)? Verhalten von nfcd bei Display-Dimming?                                                                                                                                              | Test mit App im Cover-Modus. |
| O-4 | Exakte URI-Serialisierung der Android-App (`openhab://?i=…` vs. `openhab:///?i=…`, Encoding von Sonderzeichen in Item-Namen).                                                                                                                                                           | **Kein Android-Gerät verfügbar** → Ersatzstrategie: Serialisierung aus dem Kotlin-Quelltext (`NfcTag.kt`, `WriteTagActivity.kt`) ableiten und als Golden-Byte-Vektoren in die Unit-Tests gießen. Siehe Review-Abschnitt C. |
| O-5 | Entscheidung --> mindestens 4.5 und neuer : Minimale unterstützte Sailfish-Version. nfcd ist seit ~3.0.3 vorhanden, D-Bus-Interfaces sind über die Jahre gewachsen (`GetAll2`…`GetAll6`). Welche Basis setzen wir?                                                                      | Interface-Version zur Laufzeit prüfen; Zielversion mit Maintainer festlegen. |
| O-6 | Braucht die App `RequestMode`/`RequestTechs`, oder reicht der Default-Reader-Modus? ENTSCHEIDUNG: --> Wir starten mit dem deafault-reader modus                                                                                                                                         | Spike. |
| O-7 | Entscheidung --> Wir starten mit einem hinweis und enablen nix automatisch: Ist `Settings.SetEnabled(true)` aus dem Sandbox heraus erlaubt (Policy erlaubt `send_interface`, aber evtl. greift zusätzlich eine Rechteprüfung)? Sonst nur Hinweis „NFC in den Einstellungen aktivieren“. | Aufruf testen. |
| O-8 | Entscheidung --> siehe Punkt Openhab FLOW : UX für den Schreibvorgang: eigene Seite mit „Tag auflegen“ oder Pulley-Menü im Widget-Kontext? Wo im bestehenden `SitemapPage.qml` (Long-Press ist dort noch nicht belegt)?                                                                 | Design-Abstimmung. |
| O-9 | Entscheidung --> Nein: Wollen wir Auto-Start (App geschlossen) überhaupt anbieten? Das bedeutet ein zweites Paket außerhalb des Jolla Store und damit eine zweite Distributionsschiene.                                                                                                 | Produktentscheidung. |
| O-10 | Entscheidung --> Nein, kein extra bestätigunsdialog. Sicherheit: Ein beliebiger Tag kann einen Command auslösen. Bestätigungsdialog optional anbieten? Android tut das nicht.                                                                                                           | Produktentscheidung. |

---
## Openhab FLOW

Flows:

Generell:
- Hat das Gerät keinen NFC Reader, wird das NFC-Feature im Hauptmenü "Ausgegraut", im Kontext-Menü ebenfalls.
- KEIN Autostart der App beim Auflegen des Tags.

LESEN:
- Mehrere/fremde Records auf dem TAG: Erster passender Record gewinnt
- tags werden nur erkannt, wenn app läuft + schalter in den einstellungen umgelegt wurde - kein hintergrund-daemon
- Prüfung:  bei item GET request an /rest/items/<item> ob item existiert, wenn nicht, dann Fehlermeldung „Item existiert auf diesem Server nicht" -- gleiche bei Sitemap-Pfad
- bei sitemap-pfad (base_url + "/rest/sitemaps" + pfad) wird in der app die entsprechende sitemap geöffnet,  settings.lastVisitedPage wird mit der neuen sitemap überschrieben + pageStack.clear()+push
- bei item wird der entsprechende command für das item per REST gesendet (bestehender flow: sendCommand(): siehe Details weiter unten unter Backend/sendCommand)
- DEPRECATED-Values werden beim lesen unterstützt.
- Item: Bei Ausführung wird eine Notification über Nemo.Notifications (In notifications-view) geschickt. Aktion Itemlabel + Command war erfolgreich oder nicht erfolgreich.

--> frage an den agenten: gibt es aus den dort gespeicherten Feldern sonst noch relevante Infos mit denen man etwas anfangen könnte? wie ist das ggf. in Android?

**ANTWORT (Review 01.09.2026):** Der Tag trägt genau fünf Felder — mehr gibt die Spezifikation nicht her: `i`, `s`, `l`, `m`, `d`.

- `i` / `s` sind die Nutzlast (Item + Command), alles andere ist optional.
- `l` (Item-Label) und `m` (gemappter Anzeige-State) sind in Android reine Anzeigedaten. **Für uns sind sie wertvoller als für Android:** Beim Lesen fragen wir ohnehin `GET /rest/items/<item>` ab — ist der Server aber langsam oder nicht erreichbar, lässt sich mit `l`/`m` trotzdem eine aussagekräftige Notification bauen („Wohnzimmerlicht → Ein" statt „Licht_WZ → ON"). Deshalb: `l` und `m` beim Schreiben **immer mitschreiben**, solange sie in den Tag passen — genau dafür existiert der Long/Short-Fallback (F-5).
- `d` ist Androids Device-ID-Modus (die App ersetzt beim Auflegen `s` durch die eigene Geräte-ID, `s` steht deshalb auf `UNSUPPORTED`). Für v1 out of scope — aber ein solcher Tag muss beim Lesen **aktiv verworfen** werden, sonst senden wir wörtlich `UNSUPPORTED` an das Item.

Keine eigenen Zusatzparameter erfinden: jedes Feld außerhalb von `i/s/l/m/d` bricht die Binärkompatibilität in Richtung Android.

SCHREIBEN:
- Item: aus den eingabeparametern wird die zu schreibende URL zusammengebaut (wie android-spezifikation)
- Sitemap: Pfad hinter /rest/sitemaps wird gespeichert.
- erfolgs-Meldung, wenn schreiben erfolgreich war
- Fehlermeldung, wenn schreiben nicht erfolgreich war
- DEPRECATED-Values werden NICHT geschrieben, wir halten uns an die aktuell gültige Spezifikation.

UI:
- einstellungen:
- Detect NFC Actions (ON / OFF) -- schaltet NFC listening an oder aus., Im Demo-Modus ausgegraut und "aus"

- Main Menü:
  -- Neuer Tab "NFC"
  -- bei klick auf den tab kommen alle items die per REST befehle annehmen können
  -- (nfc-auswahl) bei klick auf ein item kommt ein auswahl-menü der verfügbaren Aktionen
  --> bestätigt man die aktion, kommt ein fenster in dem man den nfc-chip zum beschreiben vorhalten muss
  --> ist das schreiben erfolgreich, kommt ein bestätigungsfenster.
  --> ist das schreiben nicht erfolgreich, kommt eine aussagekräftige fehlermeldung

- bei jedem item (das REST befehle annehmen kann) in der Sitemap:
  -- neues kontextmenü (lang drauf klicken)
  --- hier ist ein neues Feld "Write Command to NFC Tag"
  --> es öffnet sich wieder die "nfc-auswahl" von oben mit den darauf folgenden flows.

Backend:
- Send-Command:
sendCommand() existiert zweimal dupliziert: qml/pages/SitemapPage.qml:46 und qml/cover/CoverPage.qml:19, jeweils mit eigenem getAuthHeader(). F-1 sagt „identisch zur bestehenden sendCommand()" — es gibt aber keine eine. Der
NFC-Pfad wird der dritte Aufrufer und liegt außerhalb beider Pages. Das erzwingt entweder eine Extraktion in eine gemeinsame JS-Utility (analog SitemapLoader.js) oder ins C++.
Beide sendCommand()-Varianten haben kein Error-Handling — onreadystatechange prüft nur den Erfolgsfall, sonst passiert nichts. Für Sitemap-Klicks ist das egal (der Nutzer sieht das Widget), für NFC nicht: ohne Fehlerpfad
kein F-6.
--> Lagere beide sendCommand()-Varianten in eine gemeinsame JS-Utility (analog SitemapLoader.js) aus und implementiere ein Error-Handling.

- Notifications: Wir führen Nemo.Notifications ein, Baue eine neue Uitility "NotificationManager.js" die auch erweiterbar ist (ich möchte in zukunft auch openhab benachrichtigungen darüber senden können)


---

## Review 01.09.2026 — Präzisierungen vor der Übergabe an den Entwicklungs-Agenten

Ergebnis einer Gegenprüfung des Flows gegen den tatsächlichen Code-Stand (`feature/Version0.4`). Beantwortete Punkte tragen die Entscheidung als `-->`-Zeile direkt darunter und sind mit **ENTSCHIEDEN** gekennzeichnet. **Stand 07.09.2026 trägt kein Punkt mehr die Markierung `[ENTSCHEIDUNG OFFEN]`** — der Agent muss keine Produktentscheidung selbst treffen. Offen ist nur noch Gerätewissen (O-1 bis O-3, Restfrage aus B-3), das im Spike anfällt, sowie der Wortlaut in B-15.

**Stand der Entscheidungen (07.09.2026):**

- **Alle Produktentscheidungen sind getroffen.** A-1 (eigene NFC-Sektion in `SitemapSelectionPage.qml`), A-2 (Option c), A-3 (Sitemap-Mappings bzw. `mappings[]`, sonst statische Tabelle als JSON), A-4 (Pulley-Eintrag in `SitemapPage.qml`), A-5 (Schreiben trotz ausgeschaltetem Lauschen erlaubt, im Demo-Modus nicht), B-1 (5 s Entprellung), B-2 (Lese-Handler beim Schreiben stumm), B-5 (aufliegender Tag wird ignoriert), B-6 (**keine** Lebenszyklus-Einschränkung, siehe Konsequenz dort), B-10 (Einzelmethoden zuerst), B-11 (`lastVisitedPage` auf die Root-Sitemap setzen), B-12 (Slider/Colorpicker/Colortemperaturepicker ohne Kontextmenü), B-15 (Wortlaut, siehe dort).
- Damit ist das Dokument aus Produktsicht **übergabefertig**. B-3 ist seit dem 07.09.2026 zusätzlich am Gerät geklärt (**G-7**): kein CC-/Formatierungscode nötig. Offen ist nur noch Gerätewissen, das sich nicht am Schreibtisch beantworten lässt — O-1, O-2, O-3 — sowie eine Rückfrage an den Android-Dump (**G-8**, Lock-Control-TLV).
- B-4, B-7 bis B-9, B-13 und B-14 sind technische Feststellungen mit klarer Handlungsanweisung — dort ist keine Produktentscheidung nötig.
- Der einzige verbliebene Wortlaut-Punkt: In B-15 steht als Antwort „command ausgeführt", die Begründung darüber empfiehlt aber „Command **gesendet**". Weil der String übersetzt wird, muss er einmal verbindlich festgelegt werden — Vorschlag steht in B-15.

### A. Lücken im UI-Flow

**A-1 · „Neuer Tab NFC" — Silica kennt keine Tabs.**
Die App hat keine Tab-Leiste, und Sailfish Silica bietet auch keine an; navigiert wird ausschließlich über den PageStack. Konkret vorhandene Einstiegspunkte:

- `qml/pages/SitemapSelectionPage.qml` — die eigentliche Navigationsseite mit den Sektionen *Main* / *Sitemaps* / *System* (jeweils `ListItem` + `Icon` + `Label`).

---> korrect: we will add here a new section *Main* / *Sitemaps* / *NFC* / *System* wich resolves the new url pageStack.animatorReplace(Qt.resolvedUrl("NfcPage.qml"))

**Umsetzung (gemäß Entscheidung oben):** neue Seite `qml/pages/NfcPage.qml`, erreichbar über eine **eigene `SectionHeader`-Sektion „NFC"** in `SitemapSelectionPage.qml`, eingefügt zwischen *Sitemaps* und *System*. Der Eintrag ist ein `ListItem` im Stil der vorhandenen (Icon-Vorschlag: `image://theme/icon-m-nfc`, sonst `icon-m-wlan`) mit `onClicked: pageStack.animatorReplace(Qt.resolvedUrl("NfcPage.qml"))`. Ausgegraut (`enabled: false`) wenn kein Adapter vorhanden ist oder Demo-Modus aktiv ist (A-5) — das erfüllt „im Hauptmenü ausgegraut" aus dem Flow.

Hinweis für den Agenten: `SitemapSelectionPage.qml` verwendet `animatorReplace`, nicht `animatorPush` — die Seite ersetzt sich selbst. Für `NfcPage.qml` genauso verfahren, sonst wächst der PageStack bei jedem Navigationsvorgang.

**A-2 · Woher kommt die Item-Liste auf der NFC-Seite? — ENTSCHIEDEN (Option c)**
„alle items die per REST befehle annehmen können" ist so nicht umsetzbar: `GET /rest/items` liefert *sämtliche* Items des Servers (auf produktiven Installationen leicht 300–1000, inkl. Groups), und openHAB kennt kein Flag „nimmt Commands an". Der einzige echt schreibgeschützte Typ ist `Contact` — ein Filter darauf reduziert nichts.

Optionen:

| Variante | Vorteil | Nachteil |
|---|---|---|
| **a) Items der aktuell geladenen Sitemap** (aus `sitemapModel`) | klein, kontextnah, keine zusätzliche REST-Abfrage, entspricht dem, was der Nutzer kennt | Items ohne Sitemap-Eintrag sind nicht erreichbar |
| **b) `GET /rest/items` mit Suchfeld** | vollständig | lange Ladezeit, braucht `SearchField` + lazy rendering, unübersichtlich |
| **c) a) als Default, b) hinter „Alle Items anzeigen"** | beides | mehr Aufwand |

*Empfehlung: c), zur Not a) für v1.* Ohne Festlegung baut der Agent b) und die Seite wird unbrauchbar.

--> Wir gehen mit Option C

**A-3 · Woher kommen die „verfügbaren Aktionen" pro Item?**
Muss explizit vorgegeben werden, sonst erfindet der Agent eine Tabelle. Reihenfolge der Quellen:

1. `item.commandDescription.commandOptions[]` aus der REST-Antwort (`{command, label}`) — falls vorhanden, ist das die maßgebliche Liste. `label` → `m`, `command` → `s`.
2. Kommt der Aufruf aus dem Sitemap-Kontextmenü und hat das Widget `mappings[]` (siehe `SwitchWithMappings`, `Buttongrid` in `SitemapPage.qml`), dann diese verwenden — identisch zu Androids `WriteTagActivity`.
3. Sonst statische Tabelle nach `item.type`:

| Item-Typ | Angebotene Commands |
|---|---|
| `Switch` | `ON`, `OFF` |
| `Dimmer` | `ON`, `OFF`, `INCREASE`, `DECREASE`, freier Prozentwert |
| `Rollershutter` | `UP`, `DOWN`, `STOP`, freier Prozentwert |
| `Player` | `PLAY`, `PAUSE`, `NEXT`, `PREVIOUS` |
| `Color` | `ON`, `OFF`, freier HSB-Wert |
| `Number`, `String`, `DateTime`, `Location` | Freitexteingabe |
| `Contact` | keine — Item nicht anbieten |
| `Group` | Basistyp auswerten, sonst Freitext |

--> Ich würde so vorgehen:
- Kommt aufruf aus Sitemap -- wir nehmen die da gemappten Commands als Auswahl
- kommte der aufruf aus der NFC-Seite:
-- wenn mappings[] vorhanden, dann die
-- ansonsten oben gennannte statische tabelle nach item-typ (als .json ablegen für leichte anpassung in zukunft.)

**Konsequenzen der JSON-Ablage** (vom Agenten zu beachten):

- Ablageort `qml/base/data/item-commands.json`; die Datei muss in `DISTFILES` von `harbour-openhab.pro` stehen, sonst landet sie nicht im RPM und die Auswahl bleibt zur Laufzeit leer.
- Geladen wird sie per `XMLHttpRequest` auf `Qt.resolvedUrl("../base/data/item-commands.json")` — das funktioniert für `file://`-URLs innerhalb des Sandbox-Pfads. Alternativ über `ressources.qrc` einbetten; dann ist sie allerdings nicht mehr „leicht anpassbar", was dem Zweck widerspricht. **Empfehlung: als Datei ausliefern, nicht in die qrc.**
- Beim Laden hart gegen Fehler absichern: fehlt oder bricht die Datei, muss die NFC-Seite mit einer Freitexteingabe weiterlaufen statt leer zu bleiben.
- Kein `qsTr()` in der JSON — die Labels der statischen Tabelle sind openHAB-Commands (`ON`, `UP`, …) und werden nicht übersetzt. Ein zusätzliches Anzeige-Label pro Eintrag müsste dagegen durch den Crowdin-Fluss und gehört deshalb in QML, nicht in die JSON.

**A-4 · Für Sitemap-Tags fehlt der Einstiegspunkt.**
Der Flow legt fest, *was* geschrieben wird („Pfad hinter `/rest/sitemaps`"), aber im UI-Teil gibt es keinen Ort, an dem man das auslöst — die NFC-Seite listet Items, das Kontextmenü hängt an Items. **Vorschlag:** zusätzlicher Eintrag im Pulley-Menü der `SitemapPage` („Diese Seite auf NFC-Tag schreiben"), der den aktuellen `sitemapName`/`fullApiUrl` in den bekannten Schreib-Flow gibt.

--> korrekt, neuer Pulley-Menü eintrag "Write this Sitemap to NFC TAG in SitemapPage.qml"

**A-5 · Verhalten von Demo-Modus und Master-Schalter beim *Schreiben*. — ENTSCHIEDEN**
Festgelegt ist nur das Lesen („Detect NFC Actions", im Demo-Modus ausgegraut und aus). Offen:

- Darf man Tags schreiben, während „Detect NFC Actions" **aus** ist? *Empfehlung: ja* — Schreiben ist eine explizite Nutzeraktion, der Schalter regelt nur das passive Lauschen. Sonst muss man für jeden Schreibvorgang in die Einstellungen.
- Im Demo-Modus schreiben? *Empfehlung: nein* — ein Tag, der auf `demo.openhab.org`-Items zeigt, ist wertlos. NFC-Seite und Kontextmenü-Eintrag dort ebenfalls ausgrauen.

--> beides genauso, wenn Detect NFC Actions == AUS darf man trotzdem schreiben. beim Demomodus dagegen NICHT.

### B. Technische Lücken, die der Flow noch nicht abdeckt

**B-1 · Entprellung (Debounce) — fehlt.**
nfcd meldet `TagsChanged` potenziell mehrfach, solange derselbe Tag im Feld liegt (Re-Polling, Presence-Check). Ein physisches Auflegen muss **genau einen** Command auslösen. Regel: gleiche Tag-Objektpfad-/URI-Kombination innerhalb von ~3 s ignorieren; Fenster zurücksetzen bei `Tag.Removed()`. Android hat das Problem nicht, weil dort ein Intent pro Kontakt zugestellt wird — der Punkt lässt sich also nicht aus der Android-App abschauen.

--> gleiche Tag-Objektpfad-/URI-Kombination innerhalb von 5 sekunden ignorrieren. Zurücksetzen bei tag.removed() ist ok.

**Korrektur am Schlüssel — der Objektpfad taugt nicht dafür (Beleg: G-9).** Derselbe physische Tag bekommt bei jeder Erkennung einen **neuen** Objektpfad (`/nfc0/tag0`, später `/nfc0/tag2`). Ein Schlüssel, der den Pfad enthält, ist bei jedem Auflegen verschieden — die Entprellung würde nie greifen. Zu verwenden ist stattdessen die **`NFCID1` aus `Tag.GetAll3()`** (`poll_parameters["NFCID1"]`, bei Type 2 identisch mit `TagType2.GetSerial()`), die über beide Läufe hinweg konstant blieb.

Regel also: Schlüssel = `hex(NFCID1) + "|" + URI`, Fenster 5 s, Reset bei `Removed()` und beim Wechsel in den Vordergrund. Fehlt die `NFCID1` ausnahmsweise, ersatzweise die URI allein verwenden — lieber einmal zu viel entprellt als ein Doppel-Command.

**B-2 · Lese-Handler während des Schreibens stummschalten — fehlt.**
Während der „Tag auflegen"-Dialog offen ist, darf der Lesepfad nicht feuern. Sonst löst das Überschreiben eines bereits beschriebenen Tags zusätzlich dessen alten Command aus — was in der Entwicklung der Normalfall ist, weil dieselben paar Tags dauernd neu beschrieben werden. Der `NfcManager` braucht dafür einen expliziten Zustand (`Idle` / `Listening` / `Writing`), kein bloßes Flag in QML.

--> JA, Lese-Handler wird beim schreiben stumm geschaltet

**B-3 · Fabrikneue Tags: Capability Container. — höchste Priorität, weil ausschließlich neue Tags vorliegen.**

`nfcd/tools/ndef-write/ndef-write.c` wurde am 01.09.2026 gelesen; damit ist der Schreibpfad geklärt. Der komplette Algorithmus von `write_ndef_to_type2_tag()`:

1. `TagType2.ReadAllData()` → liefert den **gesamten Datenbereich** des Tags; dessen Länge (`size`) ist zugleich die verfügbare Kapazität. `GetDataSize()` wird dafür gar nicht benutzt.
2. Kapazitätsprüfung: `tlv_size = ndef_size + 3` (Typ-Byte + 1 Längen-Byte + Terminator), bei `ndef_size >= 0xff` zusätzlich `+2` für das Drei-Byte-Längenformat. Passt `tlv_size` nicht in `size` → Abbruch mit `"NDEF is too big (%u > %u)"`.
3. Puffer der Länge `size` bauen: `0x03`, Länge, NDEF-Message, `0xFE`, Rest **mit Nullen auffüllen**.
4. `write_ndef_data_diff()` schneidet hinten ab, solange neues und gelesenes Byte identisch sind — geschrieben wird also immer ein **Präfix ab Offset 0**, kein verstreuter Diff. Sind alle Bytes gleich: „Nothing to write."
5. `TagType2.WriteData(0, data)` — Offset ist **hart 0**.

Daraus folgt für uns:

- **`WriteData(offset=0, …)` zählt relativ zum Datenbereich**, nicht absolut ab Page 0 — sonst würde das Tool UID und CC überschreiben. Die Frage ist damit beantwortet.
- **`ndef-write` fasst den Capability Container nirgends an.** Es gibt keinen Formatierungscode. Wenn ein fabrikneuer Tag einen leeren CC hat, wird entweder nfcd ihn intern behandeln, oder `ReadAllData()` liefert 0 Bytes und der Code läuft in `"no data was read, giving up"`. **Genau das ist die zu testende Vorhersage** — und der erste konkrete Handgriff im Spike (Abschnitt D, Schritt 2).
  Falls die Vorhersage eintritt, müssen wir den CC selbst per `TagType2.Write(sector, block, …)` auf Page 3 setzen (`E1 10 <size/8> 00`) — dann liegt hier zusätzlicher Aufwand, den `ndef-write` uns nicht abnimmt.
- Ein Tag ohne gültiges NDEF exponiert **kein** `org.sailfishos.nfc.NDEF`-Interface. Der Schreibpfad darf deshalb nicht auf einem vorhandenen Record aufsetzen, sondern arbeitet allein über `org.sailfishos.nfc.TagType2` — `ndef-write` prüft folgerichtig nur auf dieses Interface.
- **`ndef-write` ruft `Acquire`/`Release` überhaupt nicht auf.** T-4 (Acquire2 vor dem Schreiben) bleibt trotzdem sinnvoll, ist aber offenbar nicht zwingend. Wenn Acquire2 Probleme macht, ist der Weg ohne Acquire durch die Referenz gedeckt.
- Der Puffer wird immer auf volle `size` genullt: ein Überschreiben löscht alte, längere Inhalte zuverlässig. Das sollten wir übernehmen.

**✅ ERLEDIGT am 07.09.2026 — die Vorhersage ist widerlegt, und zwar zu unseren Gunsten.** Ein fabrikneuer NTAG213 liefert bei `ReadAllData()` sofort 144 Byte; nfcd kommt mit dem Werkszustand problemlos zurecht, weil NTAG21x **ab Werk NDEF-formatiert** ausgeliefert wird. **Es ist kein eigener Formatierungs-/CC-Code nötig**, der befürchtete Zusatzaufwand für Phase 3 entfällt. Zahlen, Speicherbild und die vollständige Antworttabelle stehen in **G-7**.

Der Test hat allerdings etwas anderes zutage gefördert: Der Datenbereich beginnt mit einem **Lock-Control-TLV**, das der Algorithmus aus `ndef-write.c` überschreiben würde. Daraus folgt eine Abweichung von der Referenzimplementierung — Begründung, Vorgehen und die konkreten Kapazitätszahlen in **G-8**. Der frühere Satz „Referenzimplementierung praktisch 1:1" (§6.2) gilt damit **nicht mehr uneingeschränkt**.

**B-4 · Eigene Fehlerbilder für nicht beschreibbare Tags.**
Der Flow kennt nur „erfolgreich / nicht erfolgreich". Zu unterscheiden sind mindestens:

- Tag ist kein Type 2 (`Tag.GetAll3()` → `type`) → „Tag-Typ wird nicht unterstützt"
- Tag schreibgeschützt / Lock-Bits gesetzt → „Tag ist schreibgeschützt"
- selbst die **kurze** URI passt nicht in `data_size` → „Tag zu klein" (F-5 deckt nur den Long→Short-Fallback ab, nicht dessen Scheitern)
- Tag während des Schreibens entfernt (`Removed()`) → „Tag zu früh entfernt, Inhalt evtl. unvollständig"

Nutzbare Kapazität: `ndef_size + 3 <= len(ReadAllData())`, bei `ndef_size >= 0xff` zusätzlich `+2` — exakt wie in `ndef-write.c` (siehe B-3). Nicht gegen `GetDataSize()` prüfen, sondern gegen die tatsächlich gelesene Länge.

**B-5 · Tag liegt beim Aktivieren bereits auf. — ENTSCHIEDEN**
Wird „Detect NFC Actions" eingeschaltet oder die App in den Vordergrund geholt, während ein Tag im Feld liegt, liefert `Adapter.GetTags()` ihn sofort. *Empfehlung: ignorieren* — nur Tags verarbeiten, die **nach** Beginn des Lauschens neu erscheinen. Sonst feuert die App beim Start ungewollt einen Command.

--> Ja, ignorieren

**B-6 · Lebenszyklus-Bindung.**
Lauschen nur bei `Qt.application.state === Qt.ApplicationActive` starten/stoppen. Das definiert unser Verhalten unabhängig davon, wie O-3 (Cover/Dimming) auf dem Gerät ausgeht, und verhindert Commands, während die App nur im Cover sichtbar ist.

--> Nein, hier möchte ich auch dass actions ausgeführt werden, wenn die app nur im cover ist. Also nicht einschränken

**Konsequenz dieser Entscheidung** (vom Agenten so umzusetzen und zu testen): Gelauscht wird, solange die App **läuft** und der Schalter „Detect NFC Actions" an ist — unabhängig von `Qt.application.state`. Das schließt den Cover-Fall ein, aber eben auch den Fall „App läuft im Hintergrund, der Nutzer ist in einer ganz anderen Anwendung". Dann sendet harbour-openhab beim Auflegen eines Tags einen Command, ohne dass die App sichtbar ist. Das ist gewollt (es entspricht am ehesten dem Android-Verhalten), muss aber bewusst so bleiben:

- Der Schalter in den Einstellungen ist damit die **einzige** Bremse — Default deshalb zwingend **aus** (E-6).
- Die Notification (B-9) ist in diesem Fall die einzige Rückmeldung, die der Nutzer überhaupt sieht. Sie ist also kein „nice to have", sondern Teil des Lesepfads.
- Kollisionsrisiko mit dem System-URI-Handler (O-1) steigt: Wenn eine andere App im Vordergrund ist, kann Sailfish selbst auf den Tag reagieren. Genau dafür ist O-1 im Spike zu prüfen.
- `Qt.application.state` wird trotzdem gebraucht — aber nur für das **Entprellungsfenster** (B-1), nicht zum Abschalten: Beim Wechsel in den Vordergrund den Debounce-Cache leeren, damit derselbe Tag danach wieder funktioniert.

**B-7 · 404 sauber von Netzwerkfehlern trennen.**
Die Prüfung `GET /rest/items/<item>` darf nur bei **HTTP 404** „Item existiert auf diesem Server nicht" melden. Timeout, DNS-Fehler, 401/403 oder 5xx brauchen eigene Texte — sonst behauptet die App bei abgeschaltetem Server, das Item gäbe es nicht. Gleiches gilt für die Sitemap-Pfad-Prüfung.

**B-8 · Prozent-Encoding.**
Item-**Namen** sind in openHAB auf `[A-Za-z0-9_]` beschränkt, dort ist Encoding unkritisch. `s`, `l` und `m` sind es nicht: Commands wie HSB-Werte (`0,0,100`), Freitext-States und Labels mit Umlauten/Leerzeichen müssen beim Bauen prozent-kodiert (`encodeURIComponent`) und beim Lesen dekodiert werden. Auf C++-Seite `QUrlQuery` mit `QUrl::FullyDecoded` verwenden.

**B-9 · `NotificationManager.js` geht als reines JS nicht — technische Korrektur.**
Eine `.js`-Bibliothek in QML kann keine QML-Module importieren; `import Nemo.Notifications 1.0` ist dort nicht möglich. Stattdessen:

- `qml/components/NotificationManager.qml` — nicht-visuelles `Item`, das eine `Notification` kapselt und Funktionen wie `notify(summary, body, isError)` anbietet.
- Einmal in `qml/harbour-openhab.qml` (ApplicationWindow) instanziieren → über die ID global erreichbar, genau wie `settings`.
- Damit bleibt der Wunsch nach Erweiterbarkeit (später openHAB-Cloud-Benachrichtigungen) erfüllt, und alle Texte bleiben in QML und damit im `qsTr()`/Crowdin-Fluss.
- Paketierung: `Requires: nemo-qml-plugin-notifications-qt5` in `rpm/harbour-openhab.spec`.

--> ok, dann NotificationManager.qml

**B-10 · Lieber Einzelmethoden als `GetAllN`.**
Mit der Festlegung „Sailfish ≥ 4.5" (O-5) ist die `GetAll2…GetAll6`-Versionsakrobatik trotzdem riskant, weil unklar bleibt, welche nfcd-Version in 4.5 gegenüber 5.x steckt. Robuster: die seit jeher stabilen Einzelmethoden `GetAdapters()`, `GetTags()`, `GetInterfaces()`, `GetNdefRecords()`, `GetPayload()` verwenden und `GetAllN` nur dort, wo es einen Roundtrip wirklich spart. Das entschärft T-5 deutlich.

--> Ja ist ok -- wir machen die einzelmethoden zuerst

**B-11 · `lastVisitedPage` bei Subpage-Tags. — ENTSCHIEDEN**
Der Flow sagt: bei Sitemap-Tag `settings.lastVisitedPage` überschreiben. Aber: ein Tag kann auf eine **Unterseite** zeigen (`/rest/sitemaps/demo/0100`). `SitemapPage` akzeptiert das zwar (`isSubPage`, `SitemapPage.qml:19`), startet dann aber **kein SSE** (`SitemapPage.qml:205`) — und beim nächsten Kaltstart landet die App in dieser Unterseite, dauerhaft ohne Live-Updates. *Empfehlung:* zur Unterseite navigieren, `lastVisitedPage` aber nur bei einer Root-Sitemap überschreiben.

Zusätzlich: `pageStack.clear()` verwirft eine ggf. offene Settings-Seite samt ungespeicherter Eingaben. Falls das stören soll, vorher auf `pageStack.busy` / offenen Dialog prüfen.

--> bei einer sub-page überschreiben wir settings.lastVisitedPage mit der root-sitemap drüber. dann landet der nutzer nicht auf der unterseite aber zumindest eins drüber

**Umsetzung — die beiden Werte haben unterschiedliche Formate, das ist die Stolperfalle.** Am Code gegengeprüft (`qml/harbour-openhab.qml:70-112`, `qml/base/Settings.qml:10`, `qml/pages/SitemapPage.qml:15-27`):

- `SitemapPage.sitemapName` ist **überladen**: Beginnt der Wert mit `http`, gilt die Seite als Unterseite (`isSubPage`, Zeile 19) und `fullApiUrl` wird direkt übernommen; sonst wird `settings.base_url + "/rest/sitemaps/" + sitemapName` gebaut.
- `settings.lastVisitedPage` kennt dagegen nur drei Formen: `""`, die Sentinels `"MainUiPage"` / `"Sitemap"`, oder einen **nackten Sitemap-Namen** (`MainUiPage.qml:68`, `SitemapPage.qml:299`). Beim Kaltstart wird dieser Wert ungeprüft als `sitemapName` in die `SitemapPage` gereicht.

Für einen Tag mit dem Pfad `/<sitemap>/<pageid>` folgt daraus:

| | Wert | Ergebnis |
|---|---|---|
| Navigation (jetzt) | `sitemapName = settings.base_url + "/rest/sitemaps" + pfad` | `isSubPage === true`, Unterseite wird geöffnet, kein SSE — korrekt für diesen einen Aufruf |
| Persistenz | `settings.lastVisitedPage = <erstes Pfadsegment>` | Kaltstart landet auf der Root-Sitemap **mit** SSE |

Also: **niemals eine URL in `lastVisitedPage` schreiben.** Genau das würde die App dauerhaft ohne Live-Updates starten lassen — der Fehler, den diese Entscheidung verhindern soll. Bei einem Root-Tag (`/<sitemap>`, ein Segment) sind beide Werte identisch der nackte Name.

**B-12 · Kontextmenü: nicht jedes Delegate verträgt Long-Press.**
Die Delegates in `SitemapPage.qml` sind je Typ eigene `Component`-Blöcke mit eigenem `ListItem` (`switchComp` ab Zeile ~441, `groupComp`, `textComp` …). Ein `ContextMenu` muss also **pro Komponente** ergänzt werden, nicht einmal zentral. Festzulegen:

- **mit** Kontextmenü: `Switch`, `SwitchWithMappings`, `Rollershutter`, `Slider`, `Setpoint`, `Selection`, `Colorpicker`, `Input`, `Buttongrid`
- **ohne**: `Header`, `Frame`, `Group`, `Text`, `Chart`, `Image`, `Video`, `Webview`, `Mapview`
- **Achtung Gestenkonflikt:** `Slider`, `Colorpicker` und `Colortemperaturepicker` werten Drag-Gesten selbst aus (`posToValue` ~Zeile 1044). Dort kann Press-and-Hold mit der Wertänderung kollidieren — beim Test gezielt gegenprüfen und im Zweifel für diese drei auf das Kontextmenü verzichten.

--> ja die festlegung oben ist ok -- Slider, colorpicker und colortemperaturepicker lassen wir weg für den start.

**B-13 · Trennung für die Testbarkeit (T-7).**
C++ in zwei Klassen aufteilen:

- `NfcCodec` — rein: URI ↔ NDEF-Record ↔ TLV-Block, **keine** D-Bus-Abhängigkeit. Kommt in `tests/unittest/unittest.pro` und wird byteweise getestet.
- `NfcManager` — nur D-Bus, Adapter-/Tag-Handling, Zustandsautomat aus B-2. Wird **nicht** in den Unittest gelinkt.

Grund: der `%check`-Block in `rpm/harbour-openhab.spec` läuft ohne System-Bus und auf i486 ohne NFC-Hardware. Eine Klasse, die im Konstruktor `QDBusConnection::systemBus()` anfasst, bricht dort den Build.

Die URI-Ebene (Parsen/Bauen der `openhab://`-URI) gehört nach `qml/base/utilities/NfcUri.js` — dann greift der bestehende `tests/qmltest`-Harness (QJSEngine) ohne neue Infrastruktur.

**B-14 · Long-Record-Format.** `0xD1` als Header gilt nur für Short Records (Payload ≤ 255 Byte). Auf NTAG216 (888 Byte) kann eine lange URI das überschreiten — dann `0xC1` mit 4-Byte-Längenfeld. Entweder korrekt implementieren oder die Payload hart auf 255 Byte deckeln und in den Short-Fallback laufen.

**B-15 · Formulierung der Erfolgsmeldung.** `POST /rest/items/<item>` quittiert nur die Annahme des Commands, nicht dessen Ausführung. Die Notification sollte „Command gesendet" sagen, nicht „Aktion ausgeführt".

--> Ja, "command gesendet"

**Rückfrage, bitte einmal festnageln:** Die Antwort sagt „ausgeführt", die Begründung darüber empfiehlt „gesendet" — das ist gegenläufig. Technisch belegt ist nur „gesendet": Ein `POST /rest/items/<item>` liefert `200`/`202`, sobald openHAB den Command **entgegengenommen** hat; ob das Gerät reagiert hat, weiß die App zu diesem Zeitpunkt nicht (bei unerreichbarem Binding bleibt der Command wirkungslos, die App meldet trotzdem Erfolg).

Vorschlag, weil er beides erfüllt und ohne Zusatzaufwand auskommt — als Notification-Summary den Command selbst zeigen und das Verb weglassen:

- Erfolg: `qsTr("%1 → %2").arg(label).arg(command)` (also „Wohnzimmerlicht → EIN"), Body `qsTr("Command sent to openHAB")`.
- Fehler: `qsTr("Command failed")` + konkreter Grund aus B-7.

Wenn dir „ausgeführt" lieber ist, ist das auch in Ordnung — es muss nur **eine** Variante in den Code, weil der String über Crowdin in alle Sprachen geht und nachträgliche Änderungen dort alle Übersetzungen invalidieren.


### C. Kompatibilitätsnachweis ohne Android-Gerät (Ersatz für O-4)

Es steht **kein Android-Gerät** zur Verfügung; ein Referenztag lässt sich also nicht selbst mit der Android-App erzeugen.

**C-0 · Fremdhilfe: `tools/nfc-tag-dump.py`.** Für Community-Mitglieder, die *beide* Geräte haben, liegt ein eigenständiges, **rein lesendes** Python-Skript bereit. Der Helfer beschreibt einen Tag mit der openHAB-Android-App, führt das Skript im Terminal des Sailfish-Geräts aus und schickt die erzeugte `.log` zurück. Das Skript

- kommt ohne Installation aus (nur `python3` + `dbus-send`, beides auf Sailfish vorhanden — kein `python3-dbus`),
- ruft **nie** `WriteData`, `Write`, `Acquire`, `Release` oder `Deactivate` auf,
- protokolliert Daemon-/Adapterzustand, `Tag.GetAll3`, Interfaces, alle NDEF-Records mit Payload und `GetRawData` sowie — der eigentliche Zweck — `TagType2.ReadAllData()`, also den **kompletten Rohspeicher inklusive TLV**, als Hexdump *und* als fertig einsetzbares C-Byte-Array für die Golden-Tests,
- dekodiert die TLV-Struktur direkt mit und fragt am Ende ab, welches Item/Command der Helfer geschrieben hat.

Damit lässt sich O-4 **doch noch abschließend verifizieren** — inklusive der Frage, ob Android-Tags einen anderen CC-Zustand mitbringen als unsere fabrikneuen.

**Stand 07.09.2026: Ein Helfer hat zugesagt.** Damit rückt O-4 von „Ersatzstrategie" auf „wird belegt". Zwei Dinge sind dafür zwingend:

1. **Der Helfer muss die Skriptfassung ab 07.09.2026 bekommen.** Die vorherige Version hätte Payload und Rohspeicher als leer protokolliert — also genau die beiden Werte, um die es geht (Begründung: **G-5**). Vor dem Verschicken einmal `python3 nfc-tag-dump.py --instructions` prüfen und das Skript idealerweise vorher noch einmal selbst auf dem FP4 laufen lassen.
2. **Bitte gezielt danach fragen, was er geschrieben hat** — Item-Name, Command, ob mit Label/Mapping, und ob es ein Item- oder ein Sitemap-Tag ist. Das Skript fragt das am Ende ab; ohne diese Angaben lässt sich der Bytestrom nicht gegen eine erwartete URI prüfen. Optimal wären **zwei** Tags: einer kurz (nur `i`+`s`), einer mit Label und Mapping — dann sind die Golden-Vektoren (a) und (b) aus Schritt 2 unten direkt belegt statt abgeleitet.

3. **Beim Auswerten auf die ersten Bytes von `ReadAllData` achten.** B-3 ist inzwischen ohne fremde Hilfe geklärt (G-7), dafür hat der Dump eine neue Frage aufgeworfen: Beginnt das Speicherabbild des Android-Tags mit `01 03 a0 0c 34 03 …` (Lock-Control-TLV erhalten) oder direkt mit `03 …` (überschrieben)? Davon hängt ab, ob unser Schreibpfad führende TLVs erhalten muss — siehe **G-8**. Die Antwort steht in der ersten Zeile des Hexdumps, sie kostet keine zusätzliche Arbeit beim Helfer.

Bis dahin gilt weiterhin die aus dem Quelltext abgeleitete Ersatzstrategie:

1. **Serialisierung aus dem Quelltext ableiten.** `NfcTag.kt` und `WriteTagActivity.kt` in `openhab-android` sind öffentlich. Dort steht exakt, wie die URI gebaut wird (`Uri.Builder`: `scheme`/`authority`/`appendQueryParameter` — die Entscheidung `openhab://?i=…` vs. `openhab:///?i=…` und das Encoding fallen unmittelbar aus diesem Code). Der Agent liest die Quelle und schreibt das Ergebnis als Kommentar in `NfcUri.js` fest, mit Link auf Datei und Zeile.
2. **Golden-Byte-Vektoren.** Aus 1. mindestens vier erwartete Byte-Arrays ableiten und in `tests/unittest` als feste Erwartungswerte hinterlegen: (a) kurze Item-URI, (b) lange Item-URI mit `l`+`m`, (c) Sitemap-URI, (d) URI mit Sonderzeichen in `l`. Diese Tests sind ab jetzt die eigentliche Kompatibilitätsgarantie.

   **Ebene der Vektoren: die NDEF-Message, nicht der Rohspeicher.** Seit G-8 ist klar, dass das Speicherabbild eines Tags zusätzlich von führenden TLVs und der Tag-Größe abhängt — zwei Tags mit identischer URI können sich im Rohdump unterscheiden, ohne inkompatibel zu sein. Die Golden-Vektoren fixieren deshalb die Bytes ab `D1 01 …` (die NDEF-Message). Der TLV-Rahmen (`03 | len | … | FE`) und die Erhaltung führender TLVs gehören in **eigene** Tests gegen einen simulierten Speicherinhalt — dafür eignet sich das Werksabbild aus G-7 (`01 03 a0 0c 34 03 00 fe 00…`) als realistischer Eingangswert.
3. **Round-Trip-Test:** `parse(build(x)) == x` sowie Parsen der Deprecated-Form (`item`/`command`).
4. **Gerätetest:** eigenen Tag schreiben, mit `ndef-read` auslesen und gegen den Golden-Vektor vergleichen — beweist unsere Seite, nicht die Android-Seite.
5. **Offen bleibt** die Gegenprobe „Android liest unseren Tag". Vorschlag: nach dem Beta-Release im openHAB-Community-Thread um eine Verifikation bitten. Bis dahin gilt O-4 als *nicht abschließend verifiziert* — so auch im Changelog/Release-Text kennzeichnen.

### D. Spike-Plan mit der vorhandenen Hardware

Verfügbar: **Fairphone 4 mit Sailfish OS**, fabrikneue NFC-Tags, kein Android-Gerät.

**Schritt 0 — hat das FP4 unter Sailfish überhaupt einen nutzbaren NFC-Stack? — ✅ ERLEDIGT am 05.09.2026, Ergebnis: ja.** Adapter `/nfc0` vorhanden, gepowert, Reader/Writer-Modus, Tag wird erkannt. Siehe **G-1**. Die Befehle bleiben hier als Referenz stehen:

```shell
systemctl status nfcd
dbus-send --system --print-reply --dest=org.sailfishos.nfc.daemon \
  / org.sailfishos.nfc.Daemon.GetAdapters
```

Leere Adapterliste → vor allem Weiteren klären (anderes Gerät, Port-Status).

**Schritt 1 — Bootstrapping des ersten Testtags.** Ohne Android brauchen wir einen anderen Weg an den ersten `openhab://`-Tag. In dieser Reihenfolge versuchen:

1. `pkcon install nfcd-tools` → `ndef-write` / `ndef-read` (der bequemste Weg; Verfügbarkeit im Repo ist unklar, ggf. über Chum).
2. Ersatzweise `gdbus call --system` direkt gegen `TagType2.WriteData` mit einem von Hand gebauten Byte-Array — reicht für genau einen Testtag.
3. Ersatzweise Reihenfolge tauschen: erst den Schreibpfad (Phase 3) bauen, dann damit die Testtags für Phase 2 erzeugen.

Praktisch fällt Weg 3 ohnehin an, weil B-3 (Capability Container auf neuen Tags) sowieso als Erstes geklärt werden muss.

**Schritt 2 — die eine Frage, die den Schreibpfad entscheidet (B-3).** Fabrikneuen Tag auflegen und `TagType2.ReadAllData()` aufrufen — am einfachsten mit `tools/nfc-tag-dump.py`, das läuft auch auf dem eigenen Gerät:

```shell
python3 nfc-tag-dump.py --no-prompt
```

- Liefert `ReadAllData` **> 0 Bytes** (typisch 144 bei NTAG213): nfcd kommt mit dem leeren CC zurecht, der Schreibpfad kann 1:1 `ndef-write.c` folgen.
- Liefert es **0 Bytes** oder fehlt `org.sailfishos.nfc.TagType2` in den Interfaces: wir müssen den CC selbst schreiben (`TagType2.Write` auf Page 3), und der Aufwand für Phase 3 steigt spürbar.

Dieser eine Test kostet fünf Minuten und legt fest, wie groß der Schreibpfad wird — deshalb vor allem anderen Code.

**✅ ERLEDIGT am 07.09.2026.** Erster Lauf (05.09.) war wegen eines Werkzeugfehlers nicht verwertbar (**G-4**, **G-5**); die Wiederholung mit der korrigierten Skriptfassung lieferte 144 Byte beim ersten Versuch. Ergebnis: **erste Alternative**, der Schreibpfad bleibt klein. Details in **G-7**, die daraus folgende Abweichung von `ndef-write.c` in **G-8**.

**Schritt 3 — im Spike zu beantworten:** O-1 (System-Handler beansprucht `openhab://`?), O-2 (Signalempfang in der Sandbox), Notification-Zustellung aus der Sandbox, O-3 (Cover/Dimming).

**Konsequenz für die Phasenreihenfolge in §6.3:** Phase 2 (Lesen) und Phase 3 (Schreiben) lassen sich mit dieser Hardware nicht sauber trennen. Vorschlag: Phase 2 wird zu *„Codec + Schreiben eines Tags per Kommandozeile/Minimal-UI"*, danach erst Lesen und Command-Versand.

### E. Arbeitspakete für den Entwicklungs-Agenten

| # | Paket | Betroffene Dateien |
|---|---|---|
| E-1 | `sendCommand()`/`getAuthHeader()` aus `SitemapPage.qml:37/46` und `CoverPage.qml:10/19` in `qml/base/utilities/OpenHabApi.js` extrahieren, Error-Callback ergänzen, **beide** bisherigen Aufrufer migrieren (Cover-Aktionen dürfen sich nicht ändern) | `SitemapPage.qml`, `CoverPage.qml`, neu `OpenHabApi.js`, `harbour-openhab.pro` (DISTFILES) |
| E-2 | `NotificationManager.qml` (siehe B-9), Instanz in `harbour-openhab.qml` | neu `qml/components/NotificationManager.qml`, `qml/harbour-openhab.qml`, `rpm/harbour-openhab.spec` |
| E-3 | `NfcCodec` (rein) + Golden-Tests (Abschnitt C). Enthält den **TLV-Ketten-Walker** und den Puffer-Aufbau mit Erhalt führender TLVs (**G-8**); Kapazität zur Laufzeit aus `len(ReadAllData())` minus Kettenoffset, nicht hart kodiert | neu `src/nfccodec.{h,cpp}`, `tests/unittest/*`, `harbour-openhab.pro` |
| E-4 | `NfcUri.js` (URI bauen/parsen) + Tests im bestehenden QJSEngine-Harness | neu `qml/base/utilities/NfcUri.js`, `tests/qmltest/tst_jslogic.cpp` |
| E-5 | `NfcManager` (D-Bus, Zustandsautomat B-1/B-2/B-5), als Context-Property analog `sseManager`. **Eine** dauerhafte System-Bus-Verbindung, `Acquire2`/`Release2` um jeden Tag-Zugriff (T-4, G-4). Lauschen hängt **nur** am Settings-Schalter, nicht an `Qt.application.state` (B-6); nur Einzelmethoden, kein `GetAll6` (G-2) | neu `src/nfcmanager.{h,cpp}`, `src/harbour-openhab.cpp:22` |
| E-6 | Einstellungen: `nfcEnabled` (Default **aus**), Schalter „Detect NFC Actions", im Demo-Modus ausgegraut | `qml/base/Settings.qml`, `qml/pages/SettingsPage.qml` |
| E-7 | `NfcPage.qml` + eigene NFC-Sektion in `SitemapSelectionPage.qml` (A-1), Item-Liste nach Option c (A-2), Command-Auswahl inkl. statischer Tabelle als JSON (A-3) | neu `qml/pages/NfcPage.qml`, neu `qml/base/data/item-commands.json`, `SitemapSelectionPage.qml`, `harbour-openhab.pro` (DISTFILES) |
| E-8 | Kontextmenü „Write Command to NFC Tag" in den Widget-Komponenten (B-12) | `qml/pages/SitemapPage.qml` |
| E-9 | Lesepfad: Record-Validierungskette nach **G-3** (leerer Tag ≠ kein Record!) → URI parsen → Item-Prüfung → `sendCommand` → Notification (B-7, B-15) | `qml/harbour-openhab.qml` (globaler Handler) |
| E-10 | Sitemap-Tags: Lesen (B-11) und Schreiben (A-4) | `qml/harbour-openhab.qml`, `qml/pages/SitemapPage.qml` |
| E-11 | Build/Packaging: `QT += dbus`, `BuildRequires: pkgconfig(Qt5DBus)`, `Permissions=Internet;NFC` | `harbour-openhab.pro`, `rpm/harbour-openhab.spec`, `harbour-openhab.desktop` |

**Umsetzungsstand 07.09.2026** — alle elf Pakete sind implementiert:

| # | Status | Dateien |
|---|---|---|
| E-1 | ✅ | neu `qml/base/utilities/OpenHabApi.js`; `SitemapPage.qml` und `CoverPage.qml` delegieren jetzt dorthin, Signaturen unverändert (kein Aufrufer musste angefasst werden) |
| E-2 | ✅ | neu `qml/components/NotificationManager.qml`, Instanz in `harbour-openhab.qml`, `Requires` in der Spec |
| E-3 | ✅ | neu `src/nfccodec.{h,cpp}`, `tests/unittest/tst_nfccodec.cpp` (29 Tests), eigenes `nfccodec.pro`, `%check`-Block in der Spec |
| E-4 | ✅ | neu `qml/base/utilities/NfcUri.js`, 22 Tests im bestehenden QJSEngine-Harness |
| E-5 | ✅ | neu `src/nfcmanager.{h,cpp}`, Context-Property in `src/harbour-openhab.cpp` |
| E-6 | ✅ | `settings.nfcEnabled` (Default aus), Schalter + Hinweistext in `SettingsPage.qml` |
| E-7 | ✅ | neu `NfcPage.qml`, `NfcCommandPage.qml`, `NfcWritePage.qml`, NFC-Sektion in `SitemapSelectionPage.qml`, `qml/base/data/item-commands.json` |
| E-8 | ✅ | `ContextMenu` in sieben Delegates von `SitemapPage.qml` (Slider/Colorpicker/Colortemperaturepicker bewusst ohne, B-12) |
| E-9 | ✅ | Lesepfad in `harbour-openhab.qml` (`handleNfcTag`), Validierungskette nach G-3 |
| E-10 | ✅ | Sitemap-Tags lesen (`_nfcOpenSitemap`) und schreiben (Pulley-Eintrag in `SitemapPage.qml`) |
| E-11 | ✅ | `QT += dbus`, `BuildRequires: pkgconfig(Qt5DBus)`, `Permissions=Internet;NFC` |

**Was der Code noch nicht kann und bewusst offen bleibt:**

- Die Kommandotabelle wird einmal im `ApplicationWindow` geladen, nicht pro Seite — abweichend von der ursprünglichen A-3-Notiz, aber sonst hätten `NfcPage` und das Sitemap-Kontextmenü sie doppelt geholt.
- Der Wortlaut aus B-15 ist als „Label → Command" plus „Command sent to openHAB" umgesetzt. Falls „ausgeführt" gewünscht ist, ist es genau ein String in `harbour-openhab.qml`.
- Nichts davon ist auf Hardware gelaufen. Der C++-Teil wurde auf dieser Maschine nicht kompiliert (kein Qt/Compiler vorhanden); die Byte-Logik ist als Python-Port gegen das echte Werksabbild aus G-7 verifiziert, den Rest muss der erste `sfdk build` zeigen.

### F. Projekt-Checkliste (aus `docs/DEV-GUIDE.md`), nicht vergessen

- Alle neuen QML-/JS-Dateien in `DISTFILES` von `harbour-openhab.pro` eintragen — sonst fehlen sie im RPM.
- Version/Release sind bereits auf 0.4-1 gehoben (`.pro` **und** `.spec` stimmen überein) — beim Weiterarbeiten synchron halten, der Release-Workflow prüft Tag ↔ Spec.
- Alle nutzersichtbaren Texte mit `qsTr()` **in QML** — Texte, die im C++ entstehen, laufen am Crowdin-Fluss vorbei. C++ liefert Codes/Rohdaten, QML formuliert.
- `README.md` und `docs/USAGE.md` um das NFC-Feature ergänzen, Screenshots nachziehen.
- `rpm/harbour-openhab.changes`: Eintrag existiert bereits.
- Prüfen, ob die Privacy Policy eine Ergänzung braucht (NFC-Tag-Inhalte werden lokal verarbeitet und nicht übertragen — vermutlich unkritisch, aber laut Guide zu prüfen).
- Dieses Dokument vor dem Commit nach `docs/` verschieben (liegt aktuell untracked im Repo-Root).

### G. Gerätebefunde — Fairphone 4, Sailfish OS 5.0.0.72 (Tampella)

Zwei Läufe von `tools/nfc-tag-dump.py` auf der Zielhardware mit demselben **fabrikneuen, unbeschriebenen Tag**. Rohprotokolle: `nfc-tag-dump-20260905-163605.log` (G-1 bis G-6) und `nfc-tag-dump-20260907-135055.log` (G-7, G-8). Das ist ab hier die Faktenbasis — alles darüber im Dokument war Quelltext-Recherche.

**Gemessen (Lauf 1, 05.09.2026):**

| Gegenstand | Ergebnis |
|---|---|
| nfcd läuft, NFC systemseitig an | ja (`Settings.GetEnabled = true`) |
| Adapter | genau einer: `/nfc0`, `GetEnabled = true`, `GetPowered = true`, `GetMode = 2` (Reader/Writer) |
| nfcd-Kernversion | `daemon_version = 16785408` = `0x01002000` = `NFC_VERSION_WORD(1,2,0)` → **nfcd core 1.2.0** (master ist 1.2.7) |
| Interface-Versionen | `Daemon` = **4**, `Tag` = **5**, `NDEF` = **1**, `TagType2` = **1** |
| Tag-Erkennung | funktioniert, Objektpfad `/nfc0/tag0` |
| Tag-Eigenschaften | `Technology = 1`, `Protocol = 2`, `Type = 0`, `SEL_RES = 0x00`, `NFCID1 = 5a e5 11 e2 08 41 89` (7 Byte) |
| Interfaces am Tag | `org.sailfishos.nfc.Tag`, `org.sailfishos.nfc.TagType2` |
| `Tag.GetNdefRecords()` | **ein** Record: `/nfc0/tag0/ndef0` — obwohl der Tag leer ist |
| `TagType2.GetBlockSize` / `GetDataSize` | `4` / `144` → NTAG213-Format |
| `TagType2.ReadAllData()` | **fehlgeschlagen**: `org.sailfishos.nfc.Error.Failed: Failed to read tag data` |

**G-1 · Das größte Einzelrisiko ist weg.** Spike-Schritt 0 aus Abschnitt D ist damit bestanden: Das Fairphone 4 hat unter Sailfish einen funktionierenden NFC-Stack, meldet einen Adapter, pollt im Reader/Writer-Modus und erkennt Tags. Die Frage „ist das Feature auf dieser Hardware überhaupt testbar" ist mit ja beantwortet.

**G-2 · `GetAll6` gibt es auf dem Zielgerät nicht — B-10 ist damit keine Vorsichtsmaßnahme mehr, sondern Pflicht.** Das `Daemon`-Interface meldet Version 4. Die in §3.2 notierte Signatur `GetAll6()` stammt aus dem nfcd-**master** und ist auf Sailfish 5.0.0.72 schlicht nicht vorhanden; ein Aufruf endet in `org.freedesktop.DBus.Error.UnknownMethod`. Und 5.0.0.72 ist die *neueste* Version — auf dem laut O-5 zu unterstützenden Sailfish 4.5 wird es eher weniger sein. Der Agent verwendet deshalb ausschließlich die Einzelmethoden (`GetAdapters`, `GetTags`, `GetInterfaces`, `GetNdefRecords`, `GetPayload`) und, wo ein `GetAll` wirklich lohnt, die **niedrigste** Variante, deren Felder wir brauchen. `Tag.GetAll3` ist belegt nutzbar (Interface-Version 5 ≥ 3).

**G-3 · Ein leerer Tag exponiert trotzdem ein NDEF-Record-Objekt.** `GetNdefRecords()` liefert auf dem jungfräulichen Tag `/nfc0/tag0/ndef0` mit `TypeNameFormat = 0` (Empty) und leerem Type/Payload. **Folge für den Lesepfad:** Die Existenz eines Records in `GetNdefRecords()` darf **nicht** als „Tag ist beschrieben" gewertet werden. Die Prüfreihenfolge muss lauten: Record vorhanden → `TypeNameFormat == 1` (Well-Known) → `Type == "U"` → Payload nicht leer → Präfixcode + URI parsen → Schema `openhab`. Fällt eine Stufe durch, gilt F-8 (stillschweigend ignorieren). Ohne diese Reihenfolge löst jeder beliebige leere Tag den Fehlerpfad aus.

*Ursache seit G-7 bekannt:* Der Werkszustand des Tags enthält ein echtes, aber **leeres** NDEF-Message-TLV (`03 00`). nfcd bildet das korrekt als einen Record mit `TypeNameFormat = 0` (Empty) ab — der Record ist also nicht erfunden, er ist nur inhaltslos.

**G-4 · `ReadAllData` schlug fehl — aber am Werkzeug, nicht am Tag. ✅ Am 07.09.2026 aufgeklärt, siehe G-7.** Ursache 1 hat sich bestätigt: Mit der korrigierten Skriptfassung liefert derselbe Tag beim **ersten** Versuch 144 Byte. Die ursprüngliche Analyse bleibt hier als Begründung für T-4 stehen. Zwei Ursachen kamen infrage:

1. **Der Tag war nicht mehr im Feld bzw. nicht mehr aktiviert.** Dafür spricht der Aufbau des Skripts: Jeder D-Bus-Aufruf ist ein eigener `dbus-send`-Prozess mit **eigener, sofort wieder geschlossener Busverbindung**. nfcd kann einen Tag deshalb zwischen zwei Aufrufen jederzeit deaktivieren — und `ReadAllData` lief erst nach rund einem Dutzend vorheriger Aufrufe. Dass nfcd den NDEF-Record beim Erkennen problemlos gelesen hatte, zeigt: Die Hardware kann den Tag lesen.
2. Der leere Capability Container verhindert den Rohzugriff — die in B-3 formulierte Vorhersage.

**Konsequenz für die App-Architektur, unabhängig davon, welche Ursache stimmt:** Der `NfcManager` muss **eine einzige, dauerhaft offene** `QDBusConnection::systemBus()`-Verbindung führen und den Tag für die Dauer von Lesen/Schreiben mit `Tag.Acquire2(true)` halten. Genau das kann `dbus-send` prinzipbedingt nicht, und genau das rettet T-4 aus dem „nice to have" ins „notwendig". Dass `ndef-write.c` ohne `Acquire` auskommt (B-3), ist kein Gegenbeweis: Das Tool hält seine GDBus-Verbindung über den gesamten Vorgang offen und ist in Millisekunden durch.

**G-5 · Parser-Bug im Dump-Skript — die NDEF-Werte in diesem Log sind wertlos.** `parse_bytes()` erwartete dezimale `byte N`-Einträge; `dbus-send` gibt Byte-Arrays aber als **Hex-Paare** aus (`array of bytes [ 5a e5 11 … ]`). Belegt im Log selbst: `TagType2.GetSerial` wird als leer protokolliert, obwohl dieselben sieben Bytes in der `GetAll`-Rohantwort direkt darüber stehen.

- Am 07.09.2026 korrigiert (beide Formen werden jetzt akzeptiert, gegen die echte Ausgabe aus diesem Log geprüft).
- **Alle „(empty)"-Angaben zu NDEF-Type/-Id/-Payload/-RawData in diesem Log sind deshalb nicht belastbar** — sie können echt leer oder Parser-Artefakt sein. Belastbar sind nur die Werte, die *nicht* durch `parse_bytes` liefen: Adapter-, Daemon- und Tag-Eigenschaften, die Interface-Listen und der `ReadAllData`-Fehler.
- **Wichtig für die Fremdhilfe (C-0):** Ein Android-Tag-Dump mit der alten Skriptversion hätte genau das geliefert, worauf es ankommt — Payload und Rohspeicher — und zwar leer. Der Helfer muss zwingend die **aktuelle** Fassung bekommen.

**G-6 · Was als Nächstes auf dem Gerät zu tun war** (Lauf 1 erledigt, siehe G-7; Lauf 2 offen):

1. Fabrikneuen Tag erneut dumpen, mit der korrigierten Skriptversion, und den Tag durchgehend aufliegen lassen. Das Skript liest den Rohspeicher jetzt **zuerst** und wiederholt `ReadAllData` bis zu fünfmal.
   - Kommen 144 Byte zurück → Ursache 1, der leere CC ist kein Problem, der Schreibpfad folgt 1:1 `ndef-write.c`.
   - Bleibt es bei `Failed to read tag data` → Ursache 2 bleibt im Rennen; dann als Gegenprobe `ndef-write` aus `nfcd-tools` auf denselben Tag ansetzen (hält seine Verbindung offen). Scheitert auch das, müssen wir den CC selbst auf Page 3 schreiben (`E1 10 12 00` für NTAG213) und der Aufwand für Phase 3 steigt.
2. Denselben Tag nach dem ersten erfolgreichen Beschreiben noch einmal dumpen — das liefert den ersten eigenen Golden-Vektor (Abschnitt C, Schritt 4).

**G-7 · Lauf vom 07.09.2026 — B-3 ist beantwortet.**

Protokoll: `nfc-tag-dump-20260907-135055.log`, gleicher Tag (`NFCID1 5a e5 11 e2 08 41 89`), korrigierte Skriptfassung. `TagType2.ReadAllData()` lieferte **beim ersten Versuch 144 Byte**:

```
0000  01 03 a0 0c 34 03 00 fe 00 00 00 00 00 00 00 00
0010  00 00 … (Rest komplett 0x00)
```

`GetSerial` liefert jetzt ebenfalls korrekt `5a e5 11 e2 08 41 89` — der Parser-Fix aus G-5 ist damit auf echter Hardware bestätigt.

**Damit sind alle Fragen aus B-3 entschieden:**

| Frage aus B-3 | Antwort |
|---|---|
| Kommt nfcd mit einem fabrikneuen Tag zurecht? | **Ja.** Kein Sonderfall, kein leerer CC. |
| Müssen wir den Capability Container selbst schreiben? | **Nein.** NTAG213 wird ab Werk NDEF-formatiert ausgeliefert; nfcd liest CC und TLV-Kette ohne Zutun. Der befürchtete Zusatzaufwand für Phase 3 entfällt ersatzlos. |
| Ist `WriteData(offset=0, …)` relativ zum Datenbereich? | **Ja, bewiesen.** Die 144 Byte beginnen mit dem Inhalt von Page 4. UID, Lock-Bytes und CC (Pages 0–3) sind nicht enthalten und damit über `WriteData` gar nicht erreichbar — man kann den Tag mit dem Schreibpfad also nicht versehentlich unbrauchbar machen. |
| Prüft man die Kapazität gegen `GetDataSize()` oder gegen `len(ReadAllData())`? | Beide liefern hier 144. Trotzdem bei `len(ReadAllData())` bleiben, wie `ndef-write.c` es tut. |

**G-8 · Neuer Befund mit Folgen für den Schreibpfad: der Tag beginnt mit einem Lock-Control-TLV.**

Die 144 Byte sind keine Rohdaten, sondern eine **TLV-Kette**:

| Offset | Bytes | Bedeutung |
|---|---|---|
| `0x000` | `01 03 a0 0c 34` | **Lock Control TLV** (Typ `0x01`, Länge 3) — beschreibt die dynamischen Lock-Bytes auf Page 40, also *außerhalb* des Datenbereichs |
| `0x005` | `03 00` | **NDEF Message TLV**, Länge 0 → leere Message |
| `0x007` | `fe` | Terminator |

Das ist die dokumentierte Werksauslieferung von NTAG213/215/216. Zwei Konsequenzen:

**(a) Das NDEF-TLV liegt nicht bei Offset 0.** Jeder Code, der stur `data[0] == 0x03` prüft, hält einen völlig normalen Tag für unbeschrieben. Der Lesepfad muss die **TLV-Kette ablaufen** (`0x00` überspringen, `0x01`/`0x02`/`0xFD` per Längenfeld überspringen, bei `0x03` zugreifen, bei `0xFE` abbrechen). Für den Lesepfad ist das meist akademisch, weil wir die Message ohnehin fertig geparst über `org.sailfishos.nfc.NDEF` bekommen — für den **Schreibpfad** ist es das nicht.

**(b) `ndef-write.c` würde dieses TLV zerstören.** Der Referenzalgorithmus baut einen Puffer über die volle Länge, setzt `0x03` auf Offset 0 und nullt den Rest — das Lock-Control-TLV ist danach weg. Der Tag funktioniert weiter (das NDEF-TLV wird ja gefunden), aber die Information über die Lock-Bytes ist fort, und das Speicherbild weicht von dem ab, was Android hinterlässt.

**Empfehlung: führende TLVs erhalten, statt `ndef-write.c` blind zu folgen.** Konkret — und bewusst *ohne* `WriteData` mit krummem Offset, weil die Blockgröße 4 beträgt:

1. `ReadAllData()` lesen, TLV-Kette ablaufen, Offset des ersten `0x03`/`0xFE`/freien Bytes bestimmen (hier: 5).
2. Puffer der vollen Länge bauen: **die führenden Bytes 1:1 aus dem gelesenen Inhalt übernehmen**, dahinter das eigene `03 | len | NDEF | FE`, Rest mit `0x00` füllen.
3. Diff wie in `ndef-write.c` (hinten abschneiden, solange identisch) und `WriteData(0, …)` — Offset bleibt 0, Blockausrichtung bleibt garantiert.

**Kapazität, damit F-5 konkrete Zahlen bekommt** (NTAG213, 144 Byte Datenbereich):

| Strategie | max. NDEF-Message | max. URI-Länge |
|---|---|---|
| Lock-Control-TLV erhalten (Empfehlung) | 136 Byte | **131 Zeichen** |
| `ndef-write.c`-Verhalten (überschreibt) | 141 Byte | 136 Zeichen |

Rechenweg: `144 − 5 (führende TLVs) − 3 (0x03 + Längenbyte + 0xFE) = 136`; davon gehen für den URI-Record `D1 01 <len> 55 <prefix>` weitere 5 Byte ab. Zum Vergleich: `openhab://?i=Licht_Wohnzimmer&s=ON&l=Wohnzimmerlicht&m=Ein` sind 58 Zeichen — die lange Form passt also auf NTAG213 bequem, der Short-Fallback aus F-5 greift erst bei sehr langen Labels. **Der Agent darf 131 trotzdem nicht hart kodieren**, sondern muss zur Laufzeit aus `len(ReadAllData())` minus Kettenoffset rechnen: NTAG215/216 und Ultralight haben andere Größen.

**G-9 · Der Tag-Objektpfad ist keine Tag-Identität.** Dritter Lauf (`nfc-tag-dump-20260907-140651.log`), **derselbe physische Tag**, identische `NFCID1` `5a e5 11 e2 08 41 89` und byte-identischer Speicherinhalt — aber der Pfad lautet jetzt `/nfc0/tag2` statt `/nfc0/tag0`. nfcd zählt pro Erkennung hoch. Folgen:

- **Entprellung (B-1) darf nicht auf dem Objektpfad aufsetzen** — Korrektur dort eingearbeitet, Schlüssel ist die `NFCID1`.
- Objektpfade dürfen **nirgends** zwischengespeichert oder über die Lebensdauer eines Kontakts hinaus als Referenz gehalten werden. Nach `Removed()` ist ein Pfad tot; ein Aufruf darauf liefert `UnknownObject`.
- Für den Nutzer sichtbare Wiedererkennung („dieser Tag zeigt bereits auf X") müsste ebenfalls über die `NFCID1` laufen. Für v1 nicht vorgesehen, aber die Grundlage ist damit geklärt.

Bestätigt hat der Lauf außerdem den korrigierten TLV-Walker: Die Kette wird auf echter Hardware sauber als Lock Control (0x000) → NDEF Message, leer (0x005) → Terminator (0x007) ausgegeben.

**G-10 · Erster Lauf der App auf dem Gerät (07.09.2026).** Nach dem Wechsel auf ein Build-Target, das nicht neuer ist als das Gerät (siehe unten), startet die App auf dem Fairphone 4 und protokolliert:

```
[D] NfcManager::onAdaptersReply:193 - [Nfc] adapters: ("/nfc0")
```

Damit ist der riskanteste Teil der Umsetzung am lebenden Objekt bestätigt: Qt5DBus linkt und läuft, die Sailjail-Permission lässt den Aufruf auf `org.sailfishos.nfc.daemon` durch, der asynchrone `GetAdapters()`-Pfad funktioniert, und das von Hand geschriebene Demarshalling des `ao`-Arrays liefert den korrekten Objektpfad. `Settings.GetEnabled` protokolliert nur im Fehlerfall — es kam keine Warnung, der zweite Dienst antwortet also ebenfalls. **O-2 ist damit für Methodenaufrufe beantwortet**; der Signalempfang (`TagsChanged`) ist noch offen, weil er erst beim eingeschalteten Lauschen greift.

**G-11 · Schreiben und Lesen am Gerät bestätigt (07.09.2026).** Erster vollständiger Durchlauf gegen einen echten openHAB-Server:

```
[Nfc] wrote 74 bytes to "/nfc0/tag3"
[Nfc] tag read: "openhab://?i=Shelly_buero_lampe&s=ON&l=B%C3%BCro%20Licht&m=ON"
```

Die **74 Byte sind der Beweis für G-8**: 5 (Lock-Control-TLV, erhalten) + 2 (TLV-Typ und Länge) + 66 (NDEF-Message) + 1 (Terminator). Hätte der Schreibpfad wie `ndef-write.c` ab Offset 0 überschrieben, wären es 69 gewesen. Die Abweichung von der Referenzimplementierung ist damit nicht nur begründet, sondern wirksam.

Der Lesepfad lief zweimal durch, der Command wurde beide Male ausgeführt (per SSE gegenbestätigt: `Shelly_buero_lampe -> ON`). Damit ist **O-2 vollständig beantwortet** — die Sandbox stellt nicht nur Methodenaufrufe, sondern auch die `TagsChanged`-Broadcasts zu. Ebenso bestätigt: Prozent-Dekodierung (`B%C3%BCro%20Licht`), Item-Prüfung vor dem Senden und der Long-URI-Pfad mit `l` und `m`.

**Gefundener Fehler (behoben):** `NotificationManager.qml` rief `Notification.setHintValue()` auf — diese Methode existiert in `nemo-qml-plugin-notifications` **nicht**; die API kennt nur `publish()`, `close()` und statische Helfer. Die Exception brach `notify()` vor dem `publish()` ab, es kam also gar keine Benachrichtigung. Beim Nachsehen fiel ein zweiter, latenter Fehler auf: `previewSummary`/`previewBody` waren nicht gesetzt — ohne dieses Paar erscheint kein Banner, sondern nur ein stiller Eintrag in der Benachrichtigungsliste. Beides korrigiert, Fehlerfall unterscheidet sich jetzt über `urgency: Notification.Critical` statt über eine womöglich nicht existierende Kategorie.

**G-12 · Rückkopplung zwischen Lese- und Schreibpfad (07.09.2026, behoben).** Beim Überschreiben eines bereits beschriebenen Sitemap-Tags las die App den alten Inhalt, statt zu schreiben — im Log dreimal hintereinander. Ursache ist eine Schleife, nicht ein einzelner Fehlgriff:

1. Ein Lesevorgang schlüpft durch (er läuft über drei asynchrone Runden, kann also beim Stummschalten bereits unterwegs sein).
2. Ein Sitemap-Tag löst `pageStack.clear()` aus — das **zerstört die Schreibseite**.
3. Deren `Component.onDestruction` ruft `cancelWrite()`, wodurch der Lesepfad wieder scharf wird.
4. Der Tag liegt weiterhin auf dem Leser → zurück zu Schritt 1.

Behoben durch eine nestbare Sperre (`suspendReading()`/`resumeReading()`), die **alle drei NFC-Seiten** für ihre gesamte Lebensdauer halten — nicht nur der Zustandsautomat während `WriteData`. Zusätzlich verwirft `onSerialReply()` jetzt Lesevorgänge, die während der Sperre eintreffen; das ist die einzige Stelle, die `tagRead` aussendet, und damit der richtige Ort dafür. Beim Entsperren werden die aktuell aufliegenden Tags wie beim Start des Lauschens ignoriert, damit der gerade beschriebene Tag nicht sofort feuert.

**Nebenbefund, der den Schreibpfad bestätigt:** `wrote 34 bytes` für `openhab:///Stein` — die URI selbst belegt nur 29 Byte. 34 ist exakt die Länge des vorher auf dem Tag stehenden `openhab:///Stein/0000`. Der Diff aus `changedPrefixLength()` verlängert den Schreibvorgang also korrekt bis zum Ende des alten Inhalts, sodass keine Reste stehen bleiben.

**G-13 · System-Handler beansprucht `openhab://`-Tags — O-1 beantwortet, nicht behebbar.** Beim Auflegen erscheint zusätzlich ein Sailfish-Dialog „NFC-Tag gefunden, URL öffnen". Das ist der in §4.3 erwähnte System-Handler `org.sailfishos.system_nfc`, registriert über `/etc/nfcd/ndef-handlers/`. Aus einer Harbour-App lässt er sich **nicht** unterdrücken: nfcd kennt kein „ich habe das behandelt", und eine eigene Handler-Konfiguration müsste nach `/etc`, was der Harbour-Validator ausschließt. Die einzige Abhilfe wäre ein zusätzliches Paket außerhalb des Jolla Store — also genau die zweite Distributionsschiene, die in O-9 abgelehnt wurde. Damit ist der Dialog eine hinzunehmende Eigenschaft und gehört in die Nutzerdokumentation, nicht in den Fehler-Backlog.

**Achtung, Build-Target:** Ein gegen ein *neueres* Sailfish gebautes RPM verlangt `libc.so.6(GLIBC_2.34)` und lässt sich auf älteren Geräten nicht installieren (`nothing provides …`). Für Release-Builds ist deshalb **`SailfishOS-4.5.0.18`** zu verwenden — das entspricht der O-5-Untergrenze und läuft auf allen neueren Geräten mit. Nicht das jeweils neueste Target nehmen, sonst bricht die Installierbarkeit für genau die Nutzer weg, die O-5 verspricht.

**Offen und durch den Android-Dump zu klären:** Ob Android das Lock-Control-TLV tatsächlich stehen lässt (die Erwartung, weil der NFC-Forum-Type-2-Standard Lock/Memory-Control-TLVs *vor* dem NDEF-TLV verlangt) oder wie `ndef-write` überschreibt. **Das ist ab sofort die zweitwichtigste Frage an das Log des Helfers** — direkt hinter der URI-Serialisierung selbst. Fängt sein Dump mit `01 03 a0 0c 34 03 …` an, ist die Empfehlung oben bestätigt; fängt er mit `03 …` an, folgen wir `ndef-write.c` und die Sache ist ebenfalls erledigt.

---

## 8. Quellen

- nfcd: https://github.com/sailfishos/nfcd — `plugins/dbus_service/*.xml`, `plugins/dbus_handlers/README`, `plugins/settings/README`, `tools/ndef-write`
- Sailjail-Permissions: https://github.com/sailfishos/sailjail-permissions
- Harbour-Validator (erlaubte Libraries/Imports/Permissions/Pfade): https://github.com/sailfishos/sdk-harbour-rpmvalidator
- Harbour Allowed Permissions: https://docs.sailfishos.org/Develop/Apps/Harbour/Allowed_Permissions/
- openhab-android: `mobile/src/main/java/org/openhab/habdroid/model/NfcTag.kt`, `ui/WriteTagActivity.kt`, `background/NfcReceiveActivity.kt`
- Forum, D-Bus-Regeln je Permission: https://forum.sailfishos.org/t/list-of-sailjail-permissions-vs-dbus-calls/12228
- Forum, NFC-Apps als Referenz (Slava Monich): https://forum.sailfishos.org/t/toward-a-native-nfc-app/16714
