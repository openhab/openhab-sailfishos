import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/PatternFormatter.js" as PatternFormatter

CoverBackground {
    Settings { id: settings }

    // Returns the Basic Auth header value when both credentials are set
    function getAuthHeader() {
        var u = settings.username_local
        var p = settings.decodePassword(settings.password_local)
        if (u && u !== "" && p && p !== "") {
            return "Basic " + Qt.btoa(u + ":" + p)
        }
        return null
    }

    function sendCommand(itemName, command) {
        if (!itemName) return;
        var xhr = new XMLHttpRequest();
        xhr.open("POST", settings.base_url + "/rest/items/" + itemName, true);
        xhr.setRequestHeader("Content-Type", "text/plain");
        var auth = getAuthHeader()
        if (auth) xhr.setRequestHeader("Authorization", auth)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status >= 200 && xhr.status < 300) {
                //refreshTimer.restart();
            }
        }
        xhr.send(command);
    }

    property string label1: ""
    property string label2: ""

    // Fetched item data: { label, state, icon } or null
    property var itemData1: null
    property var itemData2: null

    function getItemLabel(itemName, callback) {
        if (!itemName) return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", settings.base_url + "/rest/items/" + itemName, true);
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
        if (!itemName || itemName.toString().trim() === "") return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", settings.base_url + "/rest/items/" + itemName, true);
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
        var item1 = (settings.coverItem1 && typeof settings.coverItem1 === "string") ? settings.coverItem1.trim() : "";
        var item2 = (settings.coverItem2 && typeof settings.coverItem2 === "string") ? settings.coverItem2.trim() : "";
        if (item1 !== "") {
            fetchItemData(item1, function(d) {
                itemData1 = d;
                console.log("[CoverPage] fetched data for item: " + item1 + ": " + JSON.stringify(d));
            });
        }
        if (item2 !== "") {
            fetchItemData(item2, function(d) {
                itemData2 = d;
                console.log("[CoverPage] fetched data for item: " + item2 + ": " + JSON.stringify(d));
            });
        }
    }

    Component.onCompleted: {
        getItemLabel(settings.coverAction1, function(l) { label1 = l; })
        getItemLabel(settings.coverAction2, function(l) { label2 = l; })
        refreshItems()
    }

    // Periodically refresh item states while items are configured
    Timer {
        id: itemRefreshTimer
        interval: settings.coverItemRefreshTime
        running: (settings.coverItem1 && settings.coverItem1.trim() !== "")
                 || (settings.coverItem2 && settings.coverItem2.trim() !== "")
        repeat: true
        onTriggered: refreshItems()
    }

    Column {
        anchors {
            top: parent.top
            topMargin: parent.height * 0.05
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width
        spacing: 16

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            height: width
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "qrc:///cover/cover-background"
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.application.version !== "" ? "v " + Qt.application.version : "v?.?.?"
            font.pixelSize: 20
            color: Theme.secondaryColor
        }
    }

    Column {
        anchors {
            bottom: parent.bottom
            bottomMargin: parent.height * 0.18
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width * 0.95
        spacing: 6

        // ── Cover Item 1 display ──────────────────────────────────────────────
        Row {
            visible: settings.coverItem1 !== "" && itemData1 !== null
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: Theme.paddingSmall

            Image {
                id: itemIcon1
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
                visible: itemData1 !== null && itemData1.icon !== ""
                source: (itemData1 !== null && itemData1.icon !== "")
                        ? settings.base_url + "/icon/" + itemData1.icon + "?format=png&anyFormat=true"
                        : ""
                onStatusChanged: {
                    if (status === Image.Error && source.toString().indexOf("format=png") !== -1)
                        source = settings.base_url + "/icon/" + itemData1.icon + "?format=svg"
                }
            }

            Label {
                text: itemData1 !== null ? itemData1.label : ""
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                       - (itemIcon1.visible ? itemIcon1.width + parent.spacing : 0)
                       - stateLabel1.implicitWidth - parent.spacing
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }

            Label {
                id: stateLabel1
                text: itemData1 !== null ? itemData1.state : ""
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
        }

        // ── Cover Item 2 display ──────────────────────────────────────────────
        Row {
            visible: settings.coverItem2 !== "" && itemData2 !== null
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: Theme.paddingSmall

            Image {
                id: itemIcon2
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
                visible: itemData2 !== null && itemData2.icon !== ""
                source: (itemData2 !== null && itemData2.icon !== "")
                        ? settings.base_url + "/icon/" + itemData2.icon + "?format=png&anyFormat=true"
                        : ""
                onStatusChanged: {
                    if (status === Image.Error && source.toString().indexOf("format=png") !== -1)
                        source = settings.base_url + "/icon/" + itemData2.icon + "?format=svg"
                }
            }

            Label {
                text: itemData2 !== null ? itemData2.label : ""
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                       - (itemIcon2.visible ? itemIcon2.width + parent.spacing : 0)
                       - stateLabel2.implicitWidth - parent.spacing
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }

            Label {
                id: stateLabel2
                text: itemData2 !== null ? itemData2.state : ""
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
        }

        // ── Action labels (hidden when cover items are configured) ────────────
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Left Action:  " + label1 + " - " + settings.coverAction1_command
            font.pixelSize: 20
            color: Theme.primaryColor
            visible: settings.coverItem1 === "" && settings.coverItem2 === ""
                     && settings.coverAction1 !== "" && settings.coverAction1_command !== ""
            height: visible ? implicitHeight : 0
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Right Action: " + label2  + " - " + settings.coverAction2_command
            font.pixelSize: 20
            color: Theme.primaryColor
            visible: settings.coverItem1 === "" && settings.coverItem2 === ""
                     && settings.coverAction2 !== "" && settings.coverAction2_command !== ""
            height: visible ? implicitHeight : 0
        }
    }

    CoverActionList {
        enabled: settings.coverAction1 !== "" && settings.coverAction1_command !== ""
                 && settings.coverAction2 !== "" && settings.coverAction2_command !== ""
        CoverAction {
            iconSource: "image://theme/icon-cover-previous"
            onTriggered: sendCommand(settings.coverAction1, settings.coverAction1_command)
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: sendCommand(settings.coverAction2, settings.coverAction2_command)
        }
    }

    CoverActionList {
        enabled: settings.coverAction1 !== "" && settings.coverAction1_command !== ""
                 && (settings.coverAction2 === "" || settings.coverAction2_command === "")
        CoverAction {
            iconSource: "image://theme/icon-cover-previous"
            onTriggered: sendCommand(settings.coverAction1, settings.coverAction1_command)
        }
    }

    CoverActionList {
        enabled: (settings.coverAction1 === "" || settings.coverAction1_command === "")
                 && settings.coverAction2 !== "" && settings.coverAction2_command !== ""
        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: sendCommand(settings.coverAction2, settings.coverAction2_command)
        }
    }
}
