import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"

CoverBackground {
    Settings { id: settings }

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

    property string label1: ""
    property string label2: ""

    function getItemLabel(itemName, callback) {
        if (!itemName) return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", settings.base_url + "/rest/items/" + itemName, true);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status >= 200 && xhr.status < 300) {
                var response = JSON.parse(xhr.responseText);
                var label = response.label || itemName;
                if (callback) callback(label);
            }
        }
        xhr.send();
    }

    Component.onCompleted: {
        getItemLabel(settings.coverAction1, function(l) { label1 = l; })
        getItemLabel(settings.coverAction2, function(l) { label2 = l; })
    }

    Column {
        anchors {
            top: parent.top
            topMargin: parent.height * 0.05
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width
        spacing: Theme.paddingSmall

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            height: sourceSize.height * width / sourceSize.width
            smooth: true
            source: "qrc:///cover/cover-background"
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.application.version !== "" ? "v " + Qt.application.version : "v?.?.?"
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
    }

    Column {
        anchors {
            bottom: parent.bottom
            bottomMargin: parent.height * 0.18
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width
        spacing: Theme.paddingTiny

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.9
            wrapMode: Text.WordWrap
            text: "Left Action:  " + label1 + " - " + settings.coverAction1_command
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.primaryColor
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.9
            wrapMode: Text.WordWrap
            text: "Right Action: " + label2  + " - " + settings.coverAction2_command
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.primaryColor
        }
    }

    CoverActionList {
        id: coverAction

        CoverAction {
            iconSource: "image://theme/icon-cover-previous"
            onTriggered: sendCommand(settings.coverAction1, settings.coverAction1_command)
        }

        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: sendCommand(settings.coverAction2, settings.coverAction2_command)
        }
    }
}
