import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/SitemapLoader.js" as SitemapLoader

Item {
    id: root

    property PullDownMenu pullDownMenu
    property alias menuItems: menuContainer.children

    // Signal, das andere Components verbinden können
    signal sitemapSelected(string name, string label)

    Settings { id: settings }
    ListModel { id: availableSitemapModel }

    function loadAvailableSitemaps() {
        SitemapLoader.loadAvailableSitemaps(settings.base_url, availableSitemapModel)
    }

    // Automatisch laden, wenn die Component sichtbar wird
    onVisibleChanged: {
        if (visible && availableSitemapModel.count === 0) {
            console.log("[SitemapPullDownMenu] Loading sitemaps...")
            loadAvailableSitemaps()
        }
    }

    // Der eigentliche PullDownMenu mit allen Items
    PullDownMenu {
        id: actualMenu

        Component.onCompleted: {
            root.pullDownMenu = actualMenu
        }

        MenuItem {
            text: qsTr("Refresh Sitemaps")
            onClicked: {
                availableSitemapModel.clear()
                loadAvailableSitemaps()
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
            model: availableSitemapModel

            MenuItem {
                text: model.label || model.name
                onClicked: {
                    //console.log("[SitemapPullDownMenu] Selected: " + model.name)
                    root.sitemapSelected(model.name, model.label || model.name)

                    settings.lastVisitedPage = model.name
                }
            }
        }
    }

    // Container für zusätzliche Items (falls nötig)
    Item {
        id: menuContainer
    }
}
