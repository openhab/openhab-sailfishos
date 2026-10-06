import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/PatternFormatter.js" as PatternFormatter
import "../base/utilities/OpenHabApi.js" as OpenHabApi

CoverBackground {
    Settings { id: settings }

    // Delegating to the shared OpenHabApi.js. The cover keeps its own
    // notification feedback (#18) by passing the error callback through.

    function cleanSetting(value) {
        return value && typeof value === "string" ? value.trim() : ""
    }

    function itemUrl(itemName) {
        return settings.normalizeUrl(settings.base_url) + "/rest/items/" + encodeURIComponent(itemName)
    }

    function actionConfigured(itemName, command) {
        return cleanSetting(itemName) !== "" && cleanSetting(command) !== ""
    }

    function actionIcon(command, fallbackIcon) {
        var c = cleanSetting(command).toUpperCase()
        if (c === "ON") return "image://theme/icon-cover-play"
        if (c === "OFF") return "image://theme/icon-cover-pause"
        if (c === "STOP") return "image://theme/icon-cover-cancel"
        if (c === "REFRESH" || c === "UPDATE") return "image://theme/icon-cover-refresh"
        if (c === "SYNC") return "image://theme/icon-cover-sync"
        return "image://theme/" + fallbackIcon
    }

    function configuredActionIcon(command, selectedIcon, fallbackIcon) {
        selectedIcon = cleanSetting(selectedIcon)
        return selectedIcon !== "" ? "image://theme/" + selectedIcon : actionIcon(command, fallbackIcon)
    }

    function itemIconUrl(iconName) {
        return settings.normalizeUrl(settings.base_url) + "/icon/" + iconName + "?format=png&anyFormat=true"
    }

    function showCommandFailure(itemName, status) {
        var reason = status === 0 ? qsTr("Network error") : qsTr("HTTP %1").arg(status)
        // Via the app-wide NotificationManager (harbour-openhab.qml).
        notificationManager.notifyError(
            qsTr("Cover action failed"),
            qsTr("Could not send command to %1 (%2).").arg(itemName).arg(reason),
            { "transient": true,
              "expireTimeout": 5000,
              "urgency": "normal",
              "icon": "image://theme/icon-lock-warning" })
    }

    // Returns the Basic Auth header value when both credentials are set
    function getAuthHeader() {
        return OpenHabApi.authHeader(settings.apiConfig())
    }

    function sendCommand(itemName, command) {
        itemName = cleanSetting(itemName)
        command = cleanSetting(command)
        if (itemName === "" || command === "") return;
        OpenHabApi.sendCommand(settings.apiConfig(), itemName, command,
                               function() { refreshItems() },
                               function(err) { showCommandFailure(itemName, err.status) })
    }

    property string label1: ""
    property string label2: ""

    // Fetched item data: { label, state, icon } or null
    property var itemData1: null
    property var itemData2: null
    property int visibleStatusItemCount: (cleanSetting(settings.coverItem1) !== "" && itemData1 !== null ? 1 : 0)
                                         + (cleanSetting(settings.coverItem2) !== "" && itemData2 !== null ? 1 : 0)

    function getItemLabel(itemName, callback) {
        itemName = cleanSetting(itemName)
        if (itemName === "") {
            if (callback) callback("")
            return
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", itemUrl(itemName), true);
        xhr.setRequestHeader("Accept", "application/json");
        var auth = getAuthHeader()
        if (auth) xhr.setRequestHeader("Authorization", auth)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status >= 200 && xhr.status < 300) {
                var response = JSON.parse(xhr.responseText);
                var label = response.label || itemName;
                if (callback) callback(label);
            }
        }
        xhr.send();
    }

    // Fetches item data from REST API and stores { label, state, icon }
    function fetchItemData(itemName, callback) {
        itemName = cleanSetting(itemName)
        if (itemName === "") return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", itemUrl(itemName), true);
        xhr.setRequestHeader("Accept", "application/json");
        var auth = getAuthHeader()
        if (auth) xhr.setRequestHeader("Authorization", auth)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status >= 200 && xhr.status < 300) {
                try {
                    var r = JSON.parse(xhr.responseText);
                    var pat = (r.stateDescription && r.stateDescription.pattern) ? r.stateDescription.pattern : "";
                    var rawState = r.state || "N/A";
                    var displayState = (pat !== "") ? PatternFormatter.formatState(pat, rawState) : rawState;
                    var data = {
                        "label": r.label || itemName,
                        "state": displayState,
                        "icon": r.category ? r.category.toLowerCase() : ""
                    };
                    if (callback) callback(data);
                } catch (e) {
                    console.warn("[CoverPage] fetchItemData error: " + e);
                }
            }
        }
        xhr.send();
    }

    function refreshItems() {
        var item1 = cleanSetting(settings.coverItem1)
        var item2 = cleanSetting(settings.coverItem2)
        if (item1 === "") itemData1 = null
        if (item2 === "") itemData2 = null
        if (item1 !== "") {
            fetchItemData(item1, function(d) {
                itemData1 = d;
                console.log("[CoverPage] fetched data for item: " + item1 + ": " + itemData1.state);
            });
        }
        if (item2 !== "") {
            fetchItemData(item2, function(d) {
                itemData2 = d;
                console.log("[CoverPage] fetched data for item: " + item2 + ": " + itemData2.state);
            });
        }
    }

    function refreshActionLabels() {
         var action1 = cleanSetting(settings.coverAction1)
         var action2 = cleanSetting(settings.coverAction2)
         label1 = action1
         label2 = action2
         getItemLabel(action1, function(l) {
             if (cleanSetting(settings.coverAction1) === action1) label1 = l
         })
         getItemLabel(action2, function(l) {
             if (cleanSetting(settings.coverAction2) === action2) label2 = l
         })
    }

    Component.onCompleted: {
        refreshActionLabels()
        refreshItems()
    }

    // Periodically refresh item states while items are configured
    Timer {
        id: itemRefreshTimer
        interval: parseInt(settings.coverItemRefreshTime, 10)
        running: (settings.coverItem1 && settings.coverItem1.trim() !== "")
                 || (settings.coverItem2 && settings.coverItem2.trim() !== "")
        repeat: true
        onTriggered: refreshItems()
    }

    // Debounce timer: prevents multiple refreshItems() calls when several
    // settings properties change at the same time (e.g. username + password).
    Timer {
        id: _settingsChangedTimer
        interval: 300
        repeat: false
        onTriggered: {
            refreshActionLabels()
            refreshItems()
        }
    }

    // React to settings changes (e.g. after the SettingsPage is closed)
    // and update the cover immediately without waiting for the next timer tick.
    Connections {
        target: settings
        onUsername_localChanged:        _settingsChangedTimer.restart()
        onPassword_localChanged:        _settingsChangedTimer.restart()
        onBase_urlChanged:              _settingsChangedTimer.restart()
        onCoverAction1Changed:          _settingsChangedTimer.restart()
        onCoverAction1_commandChanged:  _settingsChangedTimer.restart()
        onCoverAction1_iconChanged:     _settingsChangedTimer.restart()
        onCoverAction2Changed:          _settingsChangedTimer.restart()
        onCoverAction2_commandChanged:  _settingsChangedTimer.restart()
        onCoverAction2_iconChanged:     _settingsChangedTimer.restart()
        onCoverItem1Changed:            _settingsChangedTimer.restart()
        onCoverItem2Changed:            _settingsChangedTimer.restart()
    }

    // Watermark logo. When the bottom part of the cover is taken by the action
    // legend or by a single item tile, the logo is centred in the free space
    // above it (and shrunk if it would not fit); otherwise -- nothing shown or
    // two item tiles -- it sits slightly above the centre.
    Image {
        // Top edge of the content below the logo, or -1 if the logo is free.
        readonly property real freeBottom: actionLegend.visible ? actionLegend.y
                                         : visibleStatusItemCount === 1 ? statusColumn.y
                                         : -1
        // Height/width ratio of cover-background.png (479 x 311).
        readonly property real logoRatio: 311 / 479

        anchors.horizontalCenter: parent.horizontalCenter
        y: (freeBottom >= 0 ? freeBottom / 2 : parent.height * 0.42) - height / 2
        width: freeBottom >= 0
               ? Math.min(parent.width * 0.88, (freeBottom - 2 * Theme.paddingSmall) / logoRatio)
               : parent.width * 0.88
        height: width
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: 0.2
        source: "qrc:///cover/cover-background"
    }

    // Item tiles always have the size they have when two items are shown.
    // The column hangs from the bottom (above the cover action bar), so a
    // single tile sits at the bottom and leaves the top for the logo.
    readonly property real statusTileHeight:
        (height - Theme.paddingLarge - height * 0.22 - Theme.paddingSmall) / 2

    Column {
        id: statusColumn
        anchors {
            left: parent.left
            leftMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.paddingMedium
            bottom: parent.bottom
            bottomMargin: parent.height * 0.22
        }
        spacing: Theme.paddingSmall

        // ── Cover Item 1 display ──────────────────────────────────────────────
        Item {
            visible: cleanSetting(settings.coverItem1) !== "" && itemData1 !== null
            width: parent.width
            height: visible ? statusTileHeight : 0

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.overlayBackgroundColor, 0.28)
                radius: Theme.paddingSmall
            }

            Image {
                id: itemIcon1
                anchors {
                    left: parent.left
                    leftMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.9
                visible: itemData1 !== null && itemData1.icon !== ""
                source: visible ? itemIconUrl(itemData1.icon) : ""
                onStatusChanged: {
                    if (status === Image.Error && source.toString().indexOf("format=png") !== -1)
                        source = settings.normalizeUrl(settings.base_url) + "/icon/" + itemData1.icon + "?format=svg"
                }
            }

            Column {
                anchors {
                    left: itemIcon1.visible ? itemIcon1.right : parent.left
                    leftMargin: Theme.paddingSmall
                    right: parent.right
                    rightMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                spacing: 0

                Label {
                    width: parent.width
                    text: itemData1 !== null ? itemData1.label : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    // Long item labels wrap onto a second line instead of
                    // fading out; anything beyond that is elided.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Label {
                    id: stateLabel1
                    width: parent.width
                    text: itemData1 !== null ? itemData1.state : ""
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        // ── Cover Item 2 display ──────────────────────────────────────────────
        Item {
            visible: cleanSetting(settings.coverItem2) !== "" && itemData2 !== null
            width: parent.width
            height: visible ? statusTileHeight : 0

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.overlayBackgroundColor, 0.28)
                radius: Theme.paddingSmall
            }

            Image {
                id: itemIcon2
                anchors {
                    left: parent.left
                    leftMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.9
                visible: itemData2 !== null && itemData2.icon !== ""
                source: visible ? itemIconUrl(itemData2.icon) : ""
                onStatusChanged: {
                    if (status === Image.Error && source.toString().indexOf("format=png") !== -1)
                        source = settings.normalizeUrl(settings.base_url) + "/icon/" + itemData2.icon + "?format=svg"
                }
            }

            Column {
                anchors {
                    left: itemIcon2.visible ? itemIcon2.right : parent.left
                    leftMargin: Theme.paddingSmall
                    right: parent.right
                    rightMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                spacing: 0

                Label {
                    width: parent.width
                    text: itemData2 !== null ? itemData2.label : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    // Long item labels wrap onto a second line instead of
                    // fading out; anything beyond that is elided.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Label {
                    id: stateLabel2
                    width: parent.width
                    text: itemData2 !== null ? itemData2.state : ""
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }

    // ── Action legend (only when no cover items are configured) ──────────────
    // One row per configured cover action, showing the button's own icon so
    // the description is visually tied to the button right below it.
    Column {
        id: actionLegend
        anchors {
            left: parent.left
            leftMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.paddingMedium
            bottom: parent.bottom
            bottomMargin: parent.height * 0.22
        }
        spacing: Theme.paddingSmall
        visible: cleanSetting(settings.coverItem1) === "" && cleanSetting(settings.coverItem2) === ""
                 && (actionConfigured(settings.coverAction1, settings.coverAction1_command)
                     || actionConfigured(settings.coverAction2, settings.coverAction2_command))

        Repeater {
            model: [
                {
                    "configured": actionConfigured(settings.coverAction1, settings.coverAction1_command),
                    "icon": configuredActionIcon(settings.coverAction1_command,
                                                 settings.coverAction1_icon, "icon-cover-sync"),
                    "label": label1,
                    "command": cleanSetting(settings.coverAction1_command)
                },
                {
                    "configured": actionConfigured(settings.coverAction2, settings.coverAction2_command),
                    "icon": configuredActionIcon(settings.coverAction2_command,
                                                 settings.coverAction2_icon, "icon-cover-refresh"),
                    "label": label2,
                    "command": cleanSetting(settings.coverAction2_command)
                }
            ]

            delegate: Item {
                visible: modelData.configured
                width: actionLegend.width
                height: visible ? Math.max(legendIcon.height, legendText.height) + 2 * Theme.paddingSmall : 0

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.overlayBackgroundColor, 0.28)
                    radius: Theme.paddingSmall
                }

                Image {
                    id: legendIcon
                    anchors {
                        left: parent.left
                        leftMargin: Theme.paddingSmall
                        verticalCenter: parent.verticalCenter
                    }
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                    source: modelData.icon
                }

                Column {
                    id: legendText
                    anchors {
                        left: legendIcon.right
                        leftMargin: Theme.paddingSmall
                        right: parent.right
                        rightMargin: Theme.paddingSmall
                        verticalCenter: parent.verticalCenter
                    }

                    Label {
                        width: parent.width
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        // Same as the item tiles: wrap, at most two lines.
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: modelData.command
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }
        }
    }

    CoverActionList {
        enabled: actionConfigured(settings.coverAction1, settings.coverAction1_command)
                 && actionConfigured(settings.coverAction2, settings.coverAction2_command)
        CoverAction {
            iconSource: configuredActionIcon(settings.coverAction1_command,
                                             settings.coverAction1_icon,
                                             "icon-cover-sync")
            onTriggered: sendCommand(settings.coverAction1, settings.coverAction1_command)
        }
        CoverAction {
            iconSource: configuredActionIcon(settings.coverAction2_command,
                                             settings.coverAction2_icon,
                                             "icon-cover-refresh")
            onTriggered: sendCommand(settings.coverAction2, settings.coverAction2_command)
        }
    }

    CoverActionList {
        enabled: actionConfigured(settings.coverAction1, settings.coverAction1_command)
                 && !actionConfigured(settings.coverAction2, settings.coverAction2_command)
        CoverAction {
            iconSource: configuredActionIcon(settings.coverAction1_command,
                                             settings.coverAction1_icon,
                                             "icon-cover-sync")
            onTriggered: sendCommand(settings.coverAction1, settings.coverAction1_command)
        }
    }

    CoverActionList {
        enabled: !actionConfigured(settings.coverAction1, settings.coverAction1_command)
                 && actionConfigured(settings.coverAction2, settings.coverAction2_command)
        CoverAction {
            iconSource: configuredActionIcon(settings.coverAction2_command,
                                             settings.coverAction2_icon,
                                             "icon-cover-refresh")
            onTriggered: sendCommand(settings.coverAction2, settings.coverAction2_command)
        }
    }
}
