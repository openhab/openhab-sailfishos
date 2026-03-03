import QtQuick 2.0
import QtQuick.Layouts 1.1
import Sailfish.Silica 1.0
import "../base"
import "../components"
import "../base/utilities/SitemapLoader.js" as SitemapLoader
import "../base/utilities/SseEvents.js" as SseEvents

Page {
    id: page
    allowedOrientations: Orientation.All
    property string sitemapName: ""
    property string pageTitle: sitemapName

    // Unterseiten werden mit voller URL (http...) aufgerufen → kein eigener SSE-Start
    readonly property bool isSubPage: sitemapName.indexOf("http") === 0

    Settings { id: settings }

    // Restart SSE when base_url changes
    Connections {
        target: settings
        onBase_urlChanged: {
            if (!isSubPage && sseManager) {
                console.log("[SitemapPage] base_url changed, restarting SSE...");
                SseEvents.restartSSE(sseManager, settings.base_url, sitemapModel);
                fetchSitemap();
            }
        }
    }

    readonly property string fullApiUrl: sitemapName.indexOf("http") === 0
        ? sitemapName
        : settings.base_url + "/rest/sitemaps/" + sitemapName

    ListModel {
        id: sitemapModel
        dynamicRoles: true
    }

    ListModel {
        id: availableSitemapModel
    }

    // --- Logik ---

    function loadAvailableSitemaps() {
        SitemapLoader.loadAvailableSitemaps(settings.base_url, availableSitemapModel)
    }

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
                // Insert a dummy object to define the role types for dynamicRoles
                sitemapModel.append({
                    "type": "dummy",
                    "itemName": "",
                    "itemData": { "label": "", "state": "", "item": { "name": "" } }
                });
                sitemapModel.clear();
                // --- TRAINING END ---

                var rootWidgets = (json.homepage && json.homepage.widgets) ? json.homepage.widgets : (json.widgets ? json.widgets : []);

                function unpackWidgets(widgetList) {
                    widgetList.forEach(function(widget) {
                        // Extract item name as top-level role for reliable SSE matching
                        var name = (widget.item && widget.item.name) ? widget.item.name : "";

                        if (widget.type === "Frame" && widget.widgets) {
                            sitemapModel.append({
                                "type": "Header",
                                "itemName": "",
                                "itemData": { "label": (widget.label ? widget.label.toUpperCase() : ""), "state": "" }
                            });
                            unpackWidgets(widget.widgets);
                        }
                        else if (widget.item && widget.type === "Slider") {
                            sitemapModel.append({
                                "type": widget.type || "Unknown",
                                "itemName": name,
                                "itemData": widget
                            });
                        }
                        else if (widget.item && widget.item.type === "Rollershutter") {
                            sitemapModel.append({
                                "type": "Rollershutter",
                                "itemName": name,
                                "itemData": widget
                            });
                        }
                        else {
                            sitemapModel.append({
                                "type": widget.type,
                                "itemName": name,
                                "itemData": widget
                            });
                        }
                    });
                }
                unpackWidgets(rootWidgets);

                // After async model load, rebind SSE to this (now populated) model
                SseEvents.rebindModel(sitemapModel);
                console.log("[SitemapPage] Model populated with " + sitemapModel.count + " entries, SSE rebound");

                fetchAllItemStates();
            }
        }
        xhr.open("GET", fullApiUrl);
        xhr.send();
    }


   function fetchAllItemStates() {
       var itemNames = [];
       // Collect all item names from the model using top-level itemName role
       for (var i = 0; i < sitemapModel.count; i++) {
           var entry = sitemapModel.get(i);
           if (entry.itemName && entry.itemName !== "") {
               itemNames.push(entry.itemName);
           }
       }

       if (itemNames.length === 0) return;

       var itemsUrl = settings.base_url + "/rest/items?fields=name,state";
       var xhr = new XMLHttpRequest();
       xhr.onreadystatechange = function() {
           if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
               var items = JSON.parse(xhr.responseText);
               var itemStateMap = {};

               // Build map: { "ItemName": "StateValue" }
               items.forEach(function(item) {
                   itemStateMap[item.name] = item.state;
               });

               // Update model using top-level itemName role
               for (var i = 0; i < sitemapModel.count; i++) {
                   var entry = sitemapModel.get(i);
                   if (entry.itemName && entry.itemName !== "") {
                       var newState = itemStateMap[entry.itemName];

                       if (newState !== undefined) {
                           var data = entry.itemData;
                           data.state = newState.toString();
                           sitemapModel.setProperty(i, "itemData", data);
                       }
                   }
               }
           }
       }
       xhr.open("GET", itemsUrl);
       xhr.send();
   }

   Component.onCompleted: {
      fetchSitemap();
      loadAvailableSitemaps()

      if (!isSubPage && sseManager) {
          // Top-level sitemap: start SSE connection and bind to our model
          SseEvents.startSSE(sseManager, settings.base_url, sitemapModel);
          console.log("[SitemapPage] SSE started (top-level sitemap)");
      } else if (isSubPage) {
          // Sub-page: rebind the existing SSE handler to our model
          SseEvents.rebindModel(sitemapModel);
          console.log("[SitemapPage] SSE model rebound to sub-page");
      } else {
          console.error("[SitemapPage] SSEManager not available!");
      }
   }

   Component.onDestruction: {
       if (!isSubPage && sseManager) {
           // Top-level sitemap leaving: stop SSE entirely
           SseEvents.stopSSE(sseManager);
           console.log("[SitemapPage] SSE stopped (leaving top-level sitemap)");
       } else if (isSubPage) {
           // Sub-page leaving: nothing to do, the parent page will rebind
           // when it becomes active again (handled by status change below)
           console.log("[SitemapPage] Sub-page destroyed, parent will rebind model");
       }
   }

   // When this page becomes the active (top) page again after a sub-page
   // is popped, rebind the SSE handler to our model
   property bool _wasActive: false
   onStatusChanged: {
       if (status === PageStatus.Active && _wasActive) {
           // Returning from a sub-page - rebind SSE to our model
           SseEvents.rebindModel(sitemapModel);
           console.log("[SitemapPage] SSE model rebound after returning from sub-page");
       }
       if (status === PageStatus.Active) {
           _wasActive = true;
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

                // Restart SSE on sitemap switch
                if (sseManager) {
                    SseEvents.restartSSE(sseManager, settings.base_url, sitemapModel);
                    console.log("[SitemapPage] SSE restarted after sitemap switch");
                }
            }
        }

        PushUpMenu {
            MenuItem {
                text: qsTr("Scroll to top")
                onClicked: listView.scrollToTop()
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
