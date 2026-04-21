import QtQuick 2.0
import QtQuick.Layouts 1.1
import Sailfish.Silica 1.0
import "../base"
import "../components"
import "../base/utilities/SseEvents.js" as SseEvents
import "../base/utilities/PatternFormatter.js" as PatternFormatter
import "../base/utilities/ColorUtils.js" as ColorUtils
import "../base/utilities/ImageUtils.js" as ImageUtils

Page {
    id: page
    allowedOrientations: Orientation.All
    property string sitemapName: ""
    property string pageTitle: sitemapName

    // Subpages will be called with full URL (http...) → no own SSE start
    readonly property bool isSubPage: sitemapName.indexOf("http") === 0

    Settings { id: settings }


    readonly property string fullApiUrl: sitemapName.indexOf("http") === 0
        ? sitemapName
        : settings.base_url + "/rest/sitemaps/" + sitemapName

    ListModel {
        id: sitemapModel
        dynamicRoles: true
    }

    // --- Logic ---

    function sendCommand(itemName, command) {
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

                var rootWidgets = (json.homepage && json.homepage.widgets) ? json.homepage.widgets : (json.widgets ? json.widgets : []);

                function unpackWidgets(widgetList) {
                    widgetList.forEach(function(widget) {
                        // Extract item name and state as top-level roles for reliable access
                        var name = (widget.item && widget.item.name) ? widget.item.name : "";
                        var state = (widget.state !== undefined && widget.state !== null) ? widget.state.toString() : "";
                        // Extract pattern: widget-level pattern takes priority, then stateDescription
                        var pat = widget.pattern || (widget.item && widget.item.stateDescription && widget.item.stateDescription.pattern) || "";

                        // Handle different widget types and their specific data needs
                        if (widget.type === "Frame" && widget.widgets) {
                            sitemapModel.append({
                                "type": "Header",
                                "itemName": "",
                                "itemState": "",
                                "widgetPattern": "",
                                "mappingsJson": "",
                                "itemData": { "label": (widget.label ? widget.label.toUpperCase() : ""), "state": "" }
                            });
                            unpackWidgets(widget.widgets);
                        }
                        else if (widget.item && widget.type === "Slider") {
                            sitemapModel.append({
                                "type": widget.type || "Unknown",
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": "",
                                "itemData": widget
                            });
                        }
                        else if (widget.item && widget.item.type === "Rollershutter") {
                            sitemapModel.append({
                                "type": "Rollershutter",
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": "",
                                "itemData": widget
                            });
                        }
                        // For Switch widgets with mappings, use a special type to indicate the presence of mappings
                        else if (widget.type === "Switch" && widget.mappings && widget.mappings.length > 0) {
                            sitemapModel.append({
                                "type": "SwitchWithMappings",
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": JSON.stringify(widget.mappings),
                                "itemData": widget
                            });
                        }
                        // For Selection widgets without explicit mappings, use command options from the linked item if available
                        else if (widget.item && widget.type === "Selection" && widget.mappings.length === 0) {
                            sitemapModel.append({
                                "type": widget.type,
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": JSON.stringify(widget.item.commandDescription.commandOptions),
                                "itemData": widget
                            });
                        }
                        // For Selection widgets with mappings, use the provided mappings
                        else if (widget.item && widget.type === "Selection") {
                            sitemapModel.append({
                                "type": widget.type,
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": JSON.stringify(widget.mappings),
                                "itemData": widget
                            });
                        }
                        // Default case for other widget types
                        else {
                            sitemapModel.append({
                                "type": widget.type,
                                "itemName": name,
                                "itemState": state,
                                "widgetPattern": pat,
                                "mappingsJson": "",
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
                           sitemapModel.setProperty(i, "itemState", newState.toString());
                       }
                   }
               }
           }
       }
       xhr.open("GET", itemsUrl);
       xhr.send();
   }

   Component.onCompleted: {
      fetchSitemap()

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
           // Returning from a sub-page or overlay
           if (!isSubPage && sseManager && !sseManager.active) {
               // SSE was stopped (e.g. by navigating to MainUiPage) – restart it
               SseEvents.startSSE(sseManager, settings.base_url, sitemapModel);
               console.log("[SitemapPage] SSE restarted after returning to top-level sitemap");
           } else {
               // SSE still running – just rebind to our model
               SseEvents.rebindModel(sitemapModel);
               console.log("[SitemapPage] SSE model rebound after returning from sub-page");
           }
       }
       if (status === PageStatus.Active) {
           _wasActive = true;
       }
   }


    // --- UI Components ---
    // Here you can define components per openHAB widget type to display them within the sitemap.

    // Displays openHAB icons
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
                source: parent.iconName ? settings.base_url + "/icon/" + parent.iconName + "?format=png&anyFormat=true" : ""
                onStatusChanged: {
                    if (status === Image.Error && source.toString().indexOf("format=png") !== -1) {
                        source = settings.base_url + "/icon/" + parent.iconName + "?format=svg";
                    }
                }
            }
         }
    }

    // Toolbar header with navigation icons
    Item {
        id: toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.itemSizeMedium

        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
        }

        Label {
            id: titleLabel
            text: qsTr(pageTitle)
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: menuButton.left
                rightMargin: Theme.paddingMedium
            }
            horizontalAlignment: Text.AlignLeft
            truncationMode: TruncationMode.Fade
        }

        // Sitemap/Navigation menu button
        IconButton {
            id: menuButton
            icon.source: "image://theme/icon-m-menu"
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
            }
            onClicked: {
                // Open the sitemap selection page
                var selectionPage = pageStack.animatorPush(Qt.resolvedUrl("SitemapSelectionPage.qml"))
                selectionPage.pageCompleted.connect(function(selPage) {
                    selPage.sitemapSelected.connect(function(name, label) {
                        settings.lastVisitedPage = name
                        console.log("[SitemapPage] Sitemap selected: " + settings.lastVisitedPage)

                        // Pop the selection page first to return to this SitemapPage
                        pageStack.pop()

                        // Update the current SitemapPage in-place instead of pushing a new one
                        page.sitemapName = name
                        page.pageTitle = label

                        // Restart SSE and re-fetch sitemap for the newly selected sitemap
                        SseEvents.restartSSE(sseManager, settings.base_url, sitemapModel)
                        fetchSitemap()
                    })
                })
            }
        }
    }

    SilicaListView {
        id: listView
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        model: sitemapModel
        //header: PageHeader { title: qsTr(pageTitle) }

        PushUpMenu {
            MenuItem {
                text: qsTr("Scroll to top")
                onClicked: listView.scrollToTop()
            }
        }

        delegate: Item {
            width: listView.width
            height: type === "Image" ? componentLoader.implicitHeight
                  : type === "Header" ? Theme.itemSizeSmall
                  : type === "Slider" ? Theme.itemSizeLarge
                  : Theme.itemSizeMedium

            // If new widget types are added, add them as new cases in the switch statement below and create corresponding components
            Loader {
                id: componentLoader
                width: parent.width
                anchors.top: parent.top
                property var widget: itemData
                property string currentState: model.itemState || ""
                property string pattern: model.widgetPattern || ""
                property string mappingsJson: model.mappingsJson || ""
                sourceComponent: {
                    switch(type) {
                        case "Header":              return headerComp;
                        case "Switch":              return switchComp;
                        case "SwitchWithMappings":  return switchWithMappingsComp;
                        case "Rollershutter":       return rollershutterButtonsComp;
                        case "Slider":              return sliderComp;
                        case "Selection":           return selectionComp;
                        case "Colorpicker":         return colorpickerComp;
                        case "Setpoint":            return setpointComp;
                        case "Image":               return imageComp;
                        case "Group":               return groupComp;
                        case "Text":                return widget.linkedPage ? groupComp : textComp;
                        default:                    return textComp;
                    }
                }
            }
        }
    }

    // --- Templates and Components ---

    Component {
        id: headerComp
        BackgroundItem {
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

    // Simple switch component for ON/OFF items without mappings
    Component {
        id: switchComp
        ListItem {
            id: switchListItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            onClicked: sendCommand(widget.item.name, currentState === "ON" ? "OFF" : "ON")

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
                    property string _switchLabel: widget.label ? widget.label.replace(/\s*\[.*\]/, "") : ""
                    text: _switchLabel || ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (iconLoader.visible ? iconLoader.width + parent.spacing : 0)
                                        - statusLabel.width - parent.spacing
                    color: switchListItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    id: statusLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentState ? currentState.toUpperCase() : "N/A"
                    color: currentState === "ON" ? Theme.highlightColor : Theme.secondaryColor
                    font.bold: true
                }
            }
        }
    }

    // Slider component for dimmers, rollershutters or items with percentage state, with periodic update when not being interacted with
    Component {
        id: sliderComp
        ListItem {
            id: sliderItem
            width: listView.width
            contentHeight: Theme.itemSizeLarge
            highlighted: false
            implicitHeight: Theme.itemSizeLarge

            // React to SSE-driven state changes instead of polling with a Timer
            property real _externalValue: {
                if (currentState !== undefined && currentState !== "") {
                    var v = parseFloat(currentState);
                    return isNaN(v) ? 0 : v;
                }
                return 0;
            }
            on_ExternalValueChanged: {
                if (!slider.pressed) {
                    slider.value = _externalValue;
                }
            }

            Slider {
                id: slider
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: sliderItem.width - (Theme.horizontalPageMargin * 2)

                property string _sliderLabel: widget.label ? widget.label.replace(/\s*\[.*\]/, "") : ""
                label: _sliderLabel
                minimumValue: 0
                maximumValue: 100
                value: 0
                valueText: Math.round(value) + "%"

                Component.onCompleted: {
                    var v = parseFloat(currentState);
                    value = isNaN(v) ? 0 : v;
                }

                onReleased: {
                    sendCommand(widget.item.name, Math.round(value).toString());
                }
            }
        }
    }

    // Rollershutter component with UP/STOP/DOWN buttons
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

    // Custom switch component for items with mappings, displaying a button for each mapping and highlighting the active one
    Component {
        id: switchWithMappingsComp
        ListItem {
            id: mappingsItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            highlighted: false

            // Parse mappings from the JSON string passed via the model
            readonly property var mappings: {
                if (mappingsJson && mappingsJson !== "") {
                    try {
                        return JSON.parse(mappingsJson);
                    } catch (e) {
                        console.warn("[switchWithMappingsComp] Failed to parse mappingsJson:", e);
                        return [];
                    }
                }
                return [];
            }

            // Label text without [...] part
            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Loader {
                    id: mappingsIconLoader
                    sourceComponent: smartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: if (item) item.iconName = widget.icon || ""
                    visible: widget.icon !== undefined && widget.icon !== "" && widget.icon !== "none"
                    width: visible ? Theme.iconSizeSmall : 0
                }

                Label {
                    id: mappingsLabel
                    text: displayLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                           - (mappingsIconLoader.visible ? mappingsIconLoader.width + parent.spacing : 0)
                           - buttonRow.width - parent.spacing
                    truncationMode: TruncationMode.Fade
                    color: Theme.primaryColor
                }

                Row {
                    id: buttonRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    // Calculate uniform button width from widest label
                    property real uniformWidth: {
                        var maxW = 0;
                        for (var i = 0; i < mappingsSizer.count; i++) {
                            var w = mappingsSizer.itemAt(i).implicitWidth;
                            if (w > maxW) maxW = w;
                        }
                        return maxW + Theme.paddingLarge * 2;
                    }

                    // Hidden labels to measure text widths
                    Repeater {
                        id: mappingsSizer
                        model: mappings.length
                        Label {
                            visible: false
                            text: mappings[index].label || mappings[index].command || ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }

                    Repeater {
                        model: mappings.length

                        Rectangle {
                            id: mappingBtn
                            property var mapping: mappings[index]
                            property bool isActive: currentState === mapping.command

                            width: buttonRow.uniformWidth
                            height: Theme.itemSizeExtraSmall * 0.7
                            radius: Theme.paddingSmall
                            color: isActive
                                   ? Qt.rgba(Theme.highlightColor.r, Theme.highlightColor.g, Theme.highlightColor.b, 0.5)
                                   : Qt.rgba(Theme.highlightColor.r, Theme.highlightColor.g, Theme.highlightColor.b, 0.25)
                            border.width: 1
                            border.color: Theme.highlightColor

                            Label {
                                anchors.centerIn: parent
                                text: mappingBtn.mapping.label || mappingBtn.mapping.command || ""
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                                color: Theme.highlightColor
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (widget.item && widget.item.name) {
                                        sendCommand(widget.item.name, mappingBtn.mapping.command);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Selection component for items with mappings, showing the currently active mapping and opening a selection page on click
    Component {
        id: selectionComp
        ListItem {
            id: selectionItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium

            // Parse mappings from the JSON string passed via the model
            readonly property var mappings: {
                if (mappingsJson && mappingsJson !== "") {
                    try {
                        return JSON.parse(mappingsJson);
                    } catch (e) {
                        console.warn("[selectionComp] Failed to parse mappingsJson:", e);
                        return [];
                    }
                }
                return [];
            }

            // Label text without [...] part
            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")

            // Find the label of the currently selected mapping (match by command)
            readonly property string selectedLabel: {
                for (var i = 0; i < mappings.length; i++) {
                    if (mappings[i].command === currentState) {
                        return mappings[i].label || mappings[i].command || "";
                    }
                }
                // Fallback: try to extract from widget label [...]
                var lbl = widget.label || "";
                var match = lbl.match(/\[([^\]]*)\]/);
                if (match) return match[1];
                return currentState || "";
            }

            onClicked: {
                var props = {
                    "title": displayLabel,
                    "mappings": mappings,
                    "currentCommand": currentState || "",
                    "itemName": widget.item ? widget.item.name : ""
                };
                var selPage = pageStack.animatorPush(Qt.resolvedUrl("SelectionPage.qml"), props);
                selPage.pageCompleted.connect(function(pg) {
                    pg.commandSelected.connect(function(command) {
                        if (widget.item && widget.item.name) {
                            sendCommand(widget.item.name, command);
                        }
                    });
                });
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Loader {
                    id: selectionIconLoader
                    sourceComponent: smartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: if (item) item.iconName = widget.icon || ""
                    visible: widget.icon !== undefined && widget.icon !== "" && widget.icon !== "none"
                    width: visible ? Theme.iconSizeSmall : 0
                }

                Label {
                    text: displayLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                        - (selectionIconLoader.visible ? selectionIconLoader.width + parent.spacing : 0)
                        - selectionStateLabel.width - parent.spacing
                        - selectionArrow.width - parent.spacing
                    truncationMode: TruncationMode.Fade
                    color: selectionItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                Label {
                    id: selectionStateLabel
                    text: selectedLabel
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.secondaryColor
                }

                Icon {
                    id: selectionArrow
                    source: "image://theme/icon-m-right"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Colorpicker component – shows current color as circle, opens ColorPickerPage on tap
    Component {
        id: colorpickerComp
        ListItem {
            id: colorpickerListItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium

            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")
            readonly property var hsb: ColorUtils.parseHsb(currentState)
            readonly property color displayColor: ColorUtils.hsbToColor(hsb.h, hsb.s, hsb.b)

            onClicked: {
                pageStack.animatorPush(Qt.resolvedUrl("ColorPickerPage.qml"), {
                    "itemName":           widget.item ? widget.item.name : "",
                    "itemLabel":          displayLabel,
                    "initialHue":         hsb.h,
                    "initialSaturation":  hsb.s,
                    "initialBrightness":  hsb.b,
                    "baseUrl":            settings.base_url
                });
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Loader {
                    id: iconLoader
                    sourceComponent: smartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: if (item) item.iconName = widget.icon || ""
                    visible: widget.icon !== undefined && widget.icon !== "" && widget.icon !== "none"
                    width: visible ? Theme.iconSizeSmall : 0
                }

                Label {
                    text: displayLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                        - (iconLoader.visible ? iconLoader.width + parent.spacing : 0)
                        - colorIndicator.width - parent.spacing
                        - navArrow.width - parent.spacing
                    color: colorpickerListItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }

                Rectangle {
                    id: colorIndicator
                    width: Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    color: displayColor
                    border.width: 2
                    border.color: Theme.rgba(Theme.primaryColor, 0.3)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Icon {
                    id: navArrow
                    source: "image://theme/icon-m-right"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Setpoint component with MINUS/PLUS buttons for numeric items (e.g. temperature)
    // Respects minValue, maxValue and step from the openHAB widget definition.
    Component {
        id: setpointComp
        ListItem {
            id: setpointItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            implicitHeight: Theme.itemSizeMedium
            highlighted: false

            // Parse the numeric value from state (e.g. "21.5 °C" → 21.5)
            readonly property real numericValue: {
                var s = currentState || "";
                var num = parseFloat(s);
                return isNaN(num) ? 0 : num;
            }

            // Widget boundaries and step from REST API
            readonly property real minValue: (widget.minValue !== undefined && widget.minValue !== null) ? widget.minValue : 0
            readonly property real maxValue: (widget.maxValue !== undefined && widget.maxValue !== null) ? widget.maxValue : 100
            readonly property real stepValue: (widget.step !== undefined && widget.step !== null) ? widget.step : 1

            // Label text without [...] part
            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")

            // Formatted display value using pattern or raw state
            readonly property string displayState: {
                if (currentState && currentState !== "") {
                    if (pattern && pattern !== "") {
                        return PatternFormatter.formatState(pattern, currentState);
                    }
                    return currentState;
                }
                var lbl = widget.label || "";
                var match = lbl.match(/\[([^[]*)\]/);
                if (match) return match[1];
                return "N/A";
            }

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
                    id: setpointLabel
                    text: displayLabel
                    width: parent.width
                        - (iconLoader.visible ? iconLoader.width + parent.spacing : 0)
                        - minusBtn.width - parent.spacing
                        - valueLabel.width - parent.spacing
                        - plusBtn.width
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    truncationMode: TruncationMode.Fade
                }

                IconButton {
                    id: minusBtn
                    width: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-remove"
                    enabled: numericValue > minValue
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (widget.item && widget.item.name) {
                            var newVal = numericValue - stepValue;
                            if (newVal < minValue) newVal = minValue;
                            // Round to avoid floating-point precision issues
                            var decimals = (stepValue.toString().split('.')[1] || '').length;
                            newVal = parseFloat(newVal.toFixed(decimals));
                            sendCommand(widget.item.name, newVal.toString());
                        }
                    }
                }

                Label {
                    id: valueLabel
                    text: displayState
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }

                IconButton {
                    id: plusBtn
                    width: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-add"
                    enabled: numericValue < maxValue
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        if (widget.item && widget.item.name) {
                            var newVal = numericValue + stepValue;
                            if (newVal > maxValue) newVal = maxValue;
                            var decimals = (stepValue.toString().split('.')[1] || '').length;
                            newVal = parseFloat(newVal.toFixed(decimals));
                            sendCommand(widget.item.name, newVal.toString());
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imageComp
        ListItem {
            width: listView.width
            contentHeight: imgColumn.height + Theme.paddingMedium
            implicitHeight: contentHeight
            enabled: false

            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")

            // Build image source from currentState (data:image/…;base64,…) or item state
            readonly property string imageSource: {
                var st = currentState || "";
                if (st === "") {
                    // Try to extract from label [...] as fallback
                    var lbl = widget.label || "";
                    var m = lbl.match(/\[([^[]*)\]/);
                    if (m) st = m[1];
                }
                return ImageUtils.imageSourceFromState(st);
            }

            Column {
                id: imgColumn
                width: parent.width
                spacing: Theme.paddingSmall

                // Header row with icon + label
                Row {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Theme.itemSizeSmall
                    spacing: Theme.paddingMedium
                    visible: displayLabel !== ""

                    Loader {
                        sourceComponent: smartIcon
                        onLoaded: if(item) item.iconName = widget.icon
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        text: displayLabel
                        anchors.verticalCenter: parent.verticalCenter
                        truncationMode: TruncationMode.Fade
                        width: parent.width - Theme.iconSizeSmall - Theme.paddingMedium
                    }
                }

                // The actual image
                Image {
                    id: itemImage
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    fillMode: Image.PreserveAspectFit
                    source: imageSource
                    visible: imageSource !== ""
                    asynchronous: true
                    cache: false

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: itemImage.status === Image.Loading
                        size: BusyIndicatorSize.Medium
                    }
                }

                // Error placeholder when image decoding fails (e.g. missing webp plugin)
                Label {
                    visible: imageSource !== "" && itemImage.status === Image.Error
                    text: qsTr("Image format not supported")
                    color: Theme.errorColor || Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Theme.itemSizeMedium
                    verticalAlignment: Text.AlignVCenter
                }

                // Placeholder when no image available
                Label {
                    visible: imageSource === ""
                    text: qsTr("No image available")
                    color: Theme.secondaryColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Theme.itemSizeMedium
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // Group component that navigates to a linked page if available, otherwise shows as disabled text
    Component {
        id: groupComp
        ListItem {
            id: groupItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            enabled: !!(widget.linkedPage)
            onClicked: {
                if (widget.linkedPage) {
                    pageStack.animatorPush(Qt.resolvedUrl("SitemapPage.qml"), {
                        "sitemapName": widget.linkedPage.link,
                        "pageTitle": widget.label
                    });
                }
            }

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
                    color: groupItem.enabled ? Theme.primaryColor : Theme.secondaryColor
                    width: parent.width - (Theme.iconSizeSmall * 2 + Theme.paddingMedium * 4) - Theme.paddingLarge
                    truncationMode: TruncationMode.Fade
                }

                Item {
                    width: Theme.paddingLarge
                }

                Icon {
                    source: "image://theme/icon-m-right"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!(widget.linkedPage)
                }
            }
        }
    }

    // Text component for items without a linked page, showing the state and optionally formatted with a pattern
    Component {
        id: textComp
        ListItem {
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            enabled: false

            // SSE updates provide the raw state in currentState.
            // If a pattern is present, the state is formatted with it.
            // Fallback: Parse text from [...] in label (initially from Sitemap REST call).
            readonly property string displayState: {
                if (currentState && currentState !== "") {
                    if (pattern && pattern !== "") {
                        return PatternFormatter.formatState(pattern, currentState);
                    }
                    return currentState;
                }
                var lbl = widget.label || "";
                var match = lbl.match(/\[([^[]*)\]/);
                if (match) return match[1];
                return "N/A";
            }

            // Label text and remove [...] after label description
            readonly property string displayLabel: (widget.label || "").replace(/\s*\[.*\]/, "")

            Row {
                anchors.fill: parent; anchors.leftMargin: Theme.horizontalPageMargin; anchors.rightMargin: Theme.horizontalPageMargin; spacing: Theme.paddingMedium

                Loader {
                    sourceComponent: smartIcon
                    onLoaded: if(item) item.iconName = widget.icon
                    anchors.verticalCenter: parent.verticalCenter
                }

                Label {
                    text: displayLabel
                    width: parent.width - (Theme.iconSizeSmall + Theme.paddingMedium * 2) - stateVal.width
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    id: stateVal
                    text: displayState
                    color: Theme.secondaryColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
