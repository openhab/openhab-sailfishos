import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"

Item {
    id: root

    property PullDownMenu pullDownMenu
    property alias menuItems: menuContainer.children

    // The shared sitemap model from the ApplicationWindow
    property var sitemapModel: availableSitemapModel

    // Signal that other components can connect to
    signal sitemapSelected(string name, string label)

    // The actual PullDownMenu with all items
    PullDownMenu {
        id: actualMenu

        Component.onCompleted: {
            root.pullDownMenu = actualMenu
        }

        MenuItem {
            text: qsTr("Refresh Sitemaps")
            onClicked: {
                // Call the central loadAvailableSitemaps from ApplicationWindow
                appWindow.loadAvailableSitemaps()
            }
        }

        MenuItem {
            text: qsTr("Settings")
            onClicked: pageStack.animatorPush(Qt.resolvedUrl("../pages/SettingsPage.qml"))
        }

        MenuItem {
            enabled: false
            text: qsTr("─────────────────")
        }

        MenuItem {
            text: qsTr("Main")
            onClicked: pageStack.animatorPush(Qt.resolvedUrl("../pages/MainUiPage.qml"))
        }

        Repeater {
            model: root.sitemapModel

            MenuItem {
                text: model.label || model.name
                onClicked: {
                    root.sitemapSelected(model.name, model.label || model.name)
                }
            }
        }
    }

    // Container for additional items (if needed)
    Item {
        id: menuContainer
    }
}
