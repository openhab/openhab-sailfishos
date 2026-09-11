import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/OpenHabApi.js" as OpenHabApi
import "../base/utilities/NfcUri.js" as NfcUri

/**
 * Pick the command that goes onto the tag.
 *
 * Sources, in this order:
 *   1. item.commandDescription.commandOptions from the REST response
 *   2. the widget's mappings[], when we came from a sitemap context menu
 *   3. the static per-type table from item-commands.json
 * and free text input whenever none of them yields anything.
 */
Page {
    id: commandPage
    allowedOrientations: Orientation.All

    property string itemName: ""
    property string itemLabel: ""
    property string itemType: ""
    /** JSON encoded, because ListModel roles cannot carry arrays verbatim. */
    property string mappingsJson: "[]"
    property string commandJson: "null"
    property var staticCommands: ({})

    ListModel { id: commandModel }

    property bool allowFreeText: true

    function buildCommandList() {
        commandModel.clear()

        var mappings = []
        var commandDescription = null
        try { mappings = JSON.parse(mappingsJson) || [] } catch (e) { mappings = [] }
        try { commandDescription = JSON.parse(commandJson) } catch (e) { commandDescription = null }

        var item = { type: itemType, commandDescription: commandDescription }
        var commands = OpenHabApi.commandsForItem(item, mappings, staticCommands)

        for (var i = 0; i < commands.length; i++) {
            commandModel.append({
                "command": String(commands[i].command),
                "commandLabel": String(commands[i].label)
            })
        }
    }

    /**
     * Hand the finished URI to the write page. The long form carries label and
     * mapped state, the short one is the fallback when the tag is too
     * small; both are built here so the writer never has to know about
     * openHAB.
     */
    function writeCommand(command, mappedLabel) {
        var longUri = NfcUri.buildItemUri(itemName, command, itemLabel, mappedLabel)
        var shortUri = NfcUri.buildShortItemUri(itemName, command)
        pageStack.animatorPush(Qt.resolvedUrl("NfcWritePage.qml"), {
            "uri": longUri,
            "shortUri": shortUri,
            "summary": itemLabel + " → " + (mappedLabel || command)
        })
    }

    Component.onCompleted: {
        // Anywhere inside the write flow a tag read would navigate the user
        // away mid-task, so the reader stays muted for the whole flow.
        nfcManager.suspendReading()
        buildCommandList()
    }

    Component.onDestruction: nfcManager.resumeReading()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: commandModel

        header: Column {
            width: listView.width

            PageHeader {
                title: qsTr("Choose command")
                description: commandPage.itemLabel
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: commandPage.itemName + "  ·  " + commandPage.itemType
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        delegate: ListItem {
            id: commandDelegate
            contentHeight: Theme.itemSizeSmall

            onClicked: commandPage.writeCommand(model.command, model.commandLabel)

            Label {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: model.commandLabel === model.command
                      ? model.command
                      : model.commandLabel + "  (" + model.command + ")"
                truncationMode: TruncationMode.Fade
                color: commandDelegate.highlighted ? Theme.highlightColor
                                                   : Theme.primaryColor
            }
        }

        footer: Column {
            width: listView.width
            visible: commandPage.allowFreeText

            SectionHeader {
                text: commandModel.count > 0 ? qsTr("Or enter a value")
                                             : qsTr("Enter a value")
            }

            TextField {
                id: freeTextField
                width: parent.width
                placeholderText: qsTr("Command")
                label: qsTr("Command")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    var value = text.trim()
                    if (value !== "") commandPage.writeCommand(value, "")
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator {}
    }
}
