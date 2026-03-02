import QtQuick 2.0
import QtQuick.Layouts 1.1
import Sailfish.Silica 1.0
import "../base"
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All
    property string sitemapName: ""
    property string pageTitle: sitemapName

    Settings { id: settings }

    readonly property string fullApiUrl: sitemapName.indexOf("http") === 0
        ? sitemapName
        : settings.base_url + "/rest/sitemaps/" + sitemapName

    ListModel {
        id: sitemapModel
        // Das erlaubt unterschiedliche Datentypen (Maps, Listen, Strings) in 'itemData'
        dynamicRoles: true
    }

    // --- Logik ---

    function sendCommand(itemName, command) {
        // itemName ist jetzt garantiert ein String (dank .name Zugriff in den Komponenten)
        if (!itemName) return;
        var xhr = new XMLHttpRequest();
        xhr.open("POST", settings.base_url + "/rest/items/" + itemName, true);
        xhr.setRequestHeader("Content-Type", "text/plain");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status >= 200 && xhr.status < 300) {
                //refreshTimer.restart();
            }
        }
        xhr.send(command);
    }

    function fetchSitemap() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                var json = JSON.parse(xhr.responseText);

                sitemapModel.clear();

                // --- TRAINING START ---
                // Wir fügen ein Dummy-Objekt ein, um 'itemData' als VariantMap zu definieren
                sitemapModel.append({
                    "type": "dummy",
                    "itemData": { "label": "", "state": "", "item": { "name": "" } }
                });
                sitemapModel.clear(); // Sofort wieder leer machen, der Typ der Rolle bleibt gespeichert
                // --- TRAINING END ---

                var rootWidgets = (json.homepage && json.homepage.widgets) ? json.homepage.widgets : (json.widgets ? json.widgets : []);

                function unpackWidgets(widgetList) {
                    widgetList.forEach(function(widget) {
                        if (widget.type === "Frame" && widget.widgets) {
                            // Header ebenfalls als sauberes Objekt übergeben
                            sitemapModel.append({
                                "type": "Header",
                                "itemData": { "label": (widget.label ? widget.label.toUpperCase() : ""), "state": "" }
                            });
                            unpackWidgets(widget.widgets);
                        }
                        else if (widget.item && widget.type === "Slider") {
                            sitemapModel.append({
                                "type": widget.type || "Unknown",
                                "itemData": widget
                            });
                        }
                        else if (widget.item && widget.item.type === "Rollershutter") {
                            sitemapModel.append({
                                "type": "Rollershutter",
                                "itemData": widget
                            });
                        }
                        else {
                            // WICHTIG: Sicherstellen, dass widget ein Objekt ist
                            sitemapModel.append({
                                "type": widget.type,
                                "itemData": widget
                            });
                        }
                    });
                }
                unpackWidgets(rootWidgets);
                fetchAllItemStates();
            }
        }
        xhr.open("GET", fullApiUrl);
        xhr.send();
    }


   function fetchAllItemStates() {
       var itemNames = [];
       // Sammle alle Item-Namen aus dem Model
       for (var i = 0; i < sitemapModel.count; i++) {
           var entry = sitemapModel.get(i);
           if (entry.itemData && entry.itemData.item && entry.itemData.item.name) {
               itemNames.push(entry.itemData.item.name);
           }
       }

       if (itemNames.length === 0) return;

       // Nutze die OpenHAB API, um alle States auf einmal zu holen
       var itemsUrl = settings.base_url + "/rest/items?fields=name,state";
       var xhr = new XMLHttpRequest();
       xhr.onreadystatechange = function() {
           if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
               var items = JSON.parse(xhr.responseText);
               var itemStateMap = {};

               // Map erstellen: { "ItemName": "StateValue" }
               items.forEach(function(item) {
                   itemStateMap[item.name] = item.state;
               });

               // Model einmalig und vollständig aktualisieren
               for (var i = 0; i < sitemapModel.count; i++) {
                   var entry = sitemapModel.get(i);
                   if (entry.itemData && entry.itemData.item && entry.itemData.item.name) {
                       var itemName = entry.itemData.item.name;
                       var newState = itemStateMap[itemName];

                       if (newState !== undefined && entry.itemData.state !== newState.toString()) {
                           var data = entry.itemData;
                           data.state = newState.toString();
                           sitemapModel.setProperty(i, "itemData", data);
                       }
                   }
               }
           }
       }
       xhr.open("GET", itemsUrl);
       // ACHTUNG: Hier muss ggf. Ihr Authorization Header rein, falls benötigt
       xhr.send();
   }

   Component.onCompleted: {
      fetchSitemap();

      // SSE-Signal verbinden
      if (sseManager) {
          sseManager.messageReceived.connect(onSSEMessage);
          sseManager.connectToOpenHAB(settings.base_url);
          console.log("SSE-Listener aktiviert");
      } else {
          console.error("SSEManager nicht verfügbar!");
      }
   }

   Component.onDestruction: {
       // Cleanup
       if (sseManager) {
           try {
               sseManager.messageReceived.disconnect(onSSEMessage);
           } catch (e) {
               // Fehler beim Disconnect sind normal und können ignoriert werden
           }
       }
   }


    // JavaScript Funktion, die von C++ Signal aufgerufen wird
    function handleConnectionEstablished() {
        console.log("SSE verbunden. Lade Sitemap erneut zur Statussynchronisierung.");
        fetchSitemap(); // Zweiter Ladeversuch (mit aktiver SSE Verbindung)
    }

    // Externe Slot-Funktion für C++-Signale
    function onSSEMessage(message) {
        handleSSEMessage(message);
    }

    function handleSSEMessage(message) {
        if (!message) return;

        try {
            var event = JSON.parse(message);

            if (event.type === "ItemStateEvent" || event.type === "ItemStateChangedEvent") {
                var topicParts = event.topic.split('/');
                var itemName = topicParts[2];

                var payload;
                if (typeof event.payload === "string") {
                    payload = JSON.parse(event.payload);
                } else {
                    payload = event.payload;
                }

                var newState = (payload.value !== undefined) ? payload.value : payload.state;

                if (!itemName || newState === undefined) return;

                var model = sitemapModel;
                if (!model) {
                    console.log("Fehler: sitemapModel nicht verfügbar");
                    return;
                }

                console.log("Update empfangen für:", itemName, "Neuer Wert:", newState);

                var found = false;
                for (var i = 0; i < model.count; i++) {
                    var entry = model.get(i);

                    if (entry.itemData && entry.itemData.item && entry.itemData.item.name === itemName) {
                        found = true;

                        if (entry.itemData.state === newState.toString()) {
                            break;
                        }

                        var data = entry.itemData;
                        data.state = newState.toString();
                        model.setProperty(i, "itemData", data);
                        console.log("Erfolgreich aktualisiert: Zeile", i);
                        break;
                    }
                }
            }
        } catch (e) {
            console.log("Fehler beim Message-Parsing: " + e);
        }
    }





    // --- UI Komponenten ---

    Component {
        id: smartIcon
        Item {
            width: Theme.iconSizeSmall
            height: width
            property string iconName: ""
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                smooth: true
                sourceSize.width: width
                sourceSize.height: height
                visible: parent.iconName !== "" && parent.iconName !== "none"
                source: parent.iconName ? settings.base_url + "/icon/" + parent.iconName + "?format=svg" : ""
                onStatusChanged: {
                    //console.log("[IconLoader] icon: " + parent.iconName)
                    if (status === Image.Error && source.toString().indexOf("format=svg") !== -1) {
                        source = settings.base_url + "/icon/" + parent.iconName + "?format=png";
                    }
                }
            }
         }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: sitemapModel
        header: PageHeader { title: qsTr(pageTitle) }

        SitemapPullDownMenu {
            id: sitemapMenu
            visible: listView.visible

            onSitemapSelected: {
                console.log("[SitemapPage] Sitemap selected: " + name)
                sitemapName = name
                pageTitle = label
                settings.lastVisitedPage = name
                fetchSitemap()
            }
        }

        delegate: Item {
            width: listView.width
            height: type === "Header" ? Theme.itemSizeSmall :
                    (type === "Slider" ? Theme.itemSizeLarge : Theme.itemSizeMedium)

            Loader {
                id: componentLoader
                anchors.fill: parent
                property var widget: itemData
                sourceComponent: {
                    switch(type) {
                        case "Header": return headerComp;
                        case "Switch": return switchComp;
                        case "Rollershutter":   return rollershutterButtonsComp;
                        case "Slider": return sliderComp;
                        case "Group":  return groupComp;
                        case "Text":   return widget.linkedPage ? groupComp : textComp;
                        default:       return textComp;
                    }
                }
            }
        }
    }

    // --- Templates ---

    Component {
        id: headerComp
        BackgroundItem {
            // FIX: Benutze feste Höhe oder anchors, nicht beides mischen
            height: Theme.itemSizeSmall
            width: parent.width
            Label {
                text: widget.label || ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
            }
        }
    }

    Component {
        id: switchComp
        ListItem {
            id: switchListItem
            width: listView.width // Breite explizit auf ListView beziehen
            contentHeight: Theme.itemSizeMedium
            onClicked: sendCommand(widget.item.name, widget.state === "ON" ? "OFF" : "ON")

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge

                Loader {
                    id: iconLoader
                    sourceComponent: smartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: if (item) item.iconName = widget.icon
                    visible: widget.icon !== "" && widget.icon !== "none"
                }

                Label {
                    text: widget.label || ""
                    anchors.verticalCenter: parent.verticalCenter
                    // Dynamische Breite ohne Layout-Attached-Properties
                    width: parent.width - (iconLoader.visible ? iconLoader.width + parent.spacing : 0)
                                        - statusLabel.width - parent.spacing
                    color: switchListItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    id: statusLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: widget.state ? widget.state.toUpperCase() : "N/A"
                    color: widget.state === "ON" ? Theme.highlightColor : Theme.secondaryColor
                    font.bold: true
                }
            }
        }
    }

    Component {
        id: sliderComp
        ListItem {
            id: sliderItem
            width: listView.width
            contentHeight: Theme.itemSizeLarge
            highlighted: false
            implicitHeight: Theme.itemSizeLarge

            Timer {
                id: sliderUpdateTimer
                interval: 200
                repeat: true
                running: true

                onTriggered: {
                    if (!slider.pressed && widget && widget.state) {
                        var newValue = Number(widget.state) || 0;
                        if (slider.value !== newValue) {
                            slider.value = newValue;
                        }
                    }
                }
            }

            Slider {
                id: slider
                x: Theme.horizontalPageMargin
                y: (parent.height - height) / 2
                width: parent.width - (Theme.horizontalPageMargin * 2)

                label: widget.label || ""
                minimumValue: 0
                maximumValue: 100
                value: 0
                valueText: Math.round(value) + "%"

                Component.onCompleted: {
                    value = Number(widget.state) || 0;
                }

                onReleased: {
                    sendCommand(widget.item.name, Math.round(value).toString());
                }

                onVisibleChanged: {
                    if (visible) {
                        sliderUpdateTimer.start();
                    } else {
                        sliderUpdateTimer.stop();
                    }
                }
            }

            Component.onDestruction: {
                sliderUpdateTimer.stop();
            }
        }
    }

    Component {
        id: rollershutterButtonsComp
        ListItem {
            id: shutterItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            implicitHeight: Theme.itemSizeMedium

            Row {
                x: Theme.horizontalPageMargin
                y: 0
                width: parent.width - (Theme.horizontalPageMargin * 2)
                height: parent.height
                spacing: Theme.paddingMedium

                Loader {
                    id: iconLoader
                    sourceComponent: smartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: if (item) item.iconName = widget.icon || ""
                    visible: widget.icon !== "" && widget.icon !== "none" && widget.icon !== undefined
                    width: visible ? Theme.iconSizeSmall : 0
                }

                Label {
                    id: shutterLabel
                    text: widget.label || ""
                    width: parent.width
                        - (iconLoader.visible ? iconLoader.width + parent.spacing : 0)
                        - (Theme.iconSizeMedium + parent.spacing) * 3
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    truncationMode: TruncationMode.Fade
                }

                IconButton {
                    width: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-up"
                    onClicked: if (widget.item && widget.item.name) sendCommand(widget.item.name, "UP")
                }

                IconButton {
                    width: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-stop"
                    onClicked: if (widget.item && widget.item.name) sendCommand(widget.item.name, "STOP")
                }

                IconButton {
                    width: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-down"
                    onClicked: if (widget.item && widget.item.name) sendCommand(widget.item.name, "DOWN")
                }
            }
        }
    }




    Component {
        id: groupComp
        ListItem {
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            onClicked: pageStack.animatorPush(Qt.resolvedUrl("SitemapPage.qml"), {
                            "sitemapName": widget.linkedPage.link,
                            "pageTitle": widget.label
            })

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Loader {
                    sourceComponent: smartIcon
                    onLoaded: if(item) item.iconName = widget.icon
                    anchors.verticalCenter: parent.verticalCenter
                }

                Label {
                    text: widget.label || ""
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.primaryColor
                    width: parent.width - (Theme.iconSizeSmall * 2 + Theme.paddingMedium * 4) - Theme.paddingLarge
                    truncationMode: TruncationMode.Fade
                }

                Item {
                    width: Theme.paddingLarge
                }

                Icon {
                    source: "image://theme/icon-m-right"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Component {
        id: textComp
        ListItem {
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            enabled: false
            Row {
                anchors.fill: parent; anchors.leftMargin: Theme.horizontalPageMargin; anchors.rightMargin: Theme.horizontalPageMargin; spacing: Theme.paddingMedium

                Loader {
                    sourceComponent: smartIcon
                    onLoaded: if(item) item.iconName = widget.icon
                    anchors.verticalCenter: parent.verticalCenter
                }

                Label {
                    text: widget.item.label || ""
                    width: parent.width - (Theme.iconSizeSmall + Theme.paddingMedium * 2) - stateVal.width
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    id: stateVal
                    text: widget.state ? widget.state.toString() : "N/A"
                    color: Theme.secondaryColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
