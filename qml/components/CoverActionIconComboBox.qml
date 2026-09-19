import QtQuick 2.0
import Sailfish.Silica 1.0

ComboBox {
    id: iconComboBox

    property string iconName: ""
    property var options: []
    readonly property string selectedIconName: iconNameForIndex(currentIndex)

    label: qsTr("Icon")
    currentIndex: iconIndex(iconName)

    function iconIndex(name) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].name === name) return i
        }
        return 0
    }

    function iconNameForIndex(index) {
        return index >= 0 && index < options.length ? options[index].name : ""
    }

    menu: ContextMenu {
        Repeater {
            model: iconComboBox.options

            MenuItem {
                text: modelData.label
            }
        }
    }
}
