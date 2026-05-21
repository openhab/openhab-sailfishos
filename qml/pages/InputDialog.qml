import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: inputDialog

    property string itemName: ""
    property string itemLabel: ""
    property string currentValue: ""
    property string inputHint: "text"

    signal commandSent(string value)

    canAccept: inputField.text.trim() !== ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        Column {
            id: contentColumn
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Set value")
                cancelText: qsTr("Cancel")
                title: itemLabel
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Current value: %1").arg(
                    (currentValue === "NULL" || currentValue === "UNDEF" || currentValue === "")
                        ? qsTr("(not set)")
                        : currentValue
                )
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Item { width: 1; height: Theme.paddingLarge }

            TextField {
                id: inputField
                width: parent.width
                label: itemLabel
                placeholderText: qsTr("Enter new value")
                text: (currentValue === "NULL" || currentValue === "UNDEF") ? "" : currentValue
                inputMethodHints: {
                    switch (inputHint) {
                        case "number":   return Qt.ImhFormattedNumbersOnly
                        case "date":     return Qt.ImhDate
                        case "time":     return Qt.ImhTime
                        default:         return Qt.ImhNoPredictiveText
                    }
                }
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.enabled: text.trim() !== ""
                EnterKey.onClicked: if (inputDialog.canAccept) inputDialog.accept()

                Component.onCompleted: {
                    forceActiveFocus()
                    selectAll()
                }
            }
        }

        VerticalScrollDecorator {}
    }

    onAccepted: {
        commandSent(inputField.text.trim())
    }
}