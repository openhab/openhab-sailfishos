import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: selectionPage
    allowedOrientations: Orientation.All

    property string title: ""
    property var mappings: []        // Array of { command: "...", label: "..." }
    property string currentCommand: ""
    property string itemName: ""

    signal commandSelected(string command)

    SilicaListView {
        id: selectionListView
        anchors.fill: parent
        header: PageHeader { title: selectionPage.title }

        model: ListModel {
            id: selectionListModel
        }

        delegate: ListItem {
            id: selectionItem
            width: selectionListView.width
            contentHeight: Theme.itemSizeMedium

            property bool isSelected: command === currentCommand

            onClicked: {
                currentCommand = command
                commandSelected(command)
                pageStack.pop()
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Label {
                    text: label || command || ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - checkIcon.width - parent.spacing
                    color: selectionItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeMedium
                }

                Icon {
                    id: checkIcon
                    source: "image://theme/icon-m-acknowledge"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: selectionItem.isSelected
                    color: Theme.highlightColor
                }
            }
        }
    }

    Component.onCompleted: {
        selectionListModel.clear()
        for (var i = 0; i < mappings.length; i++) {
            selectionListModel.append({
                "command": mappings[i].command || "",
                "label": mappings[i].label || mappings[i].command || ""
            })
        }
    }
}

