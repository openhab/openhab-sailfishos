import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import "../base"
import "../components"

Page {
    id: mainUiPage
    allowedOrientations: Orientation.All

    Settings { id: settings }

    Component.onCompleted: {
        console.log("[MainUiPage] loaded")
        settings.lastVisitedPage = "MainUiPage"
    }

    SilicaFlickable {
        anchors.fill: parent

        SitemapPullDownMenu {
            id: sitemapMenu
            visible: parent.visible

            onSitemapSelected: {
                console.log("[MainUiPage] Sitemap selected: " + name)
                pageStack.animatorPush(Qt.resolvedUrl("SitemapPage.qml"), {
                    "sitemapName": name,
                    "pageTitle": label
                })
            }
        }

        PushUpMenu {
            MenuItem {
                text: qsTr("Scroll to top")
                onClicked: view.scrollToTop()
            }
        }

        Column {
            id: column
            width: mainUiPage.width
            height: mainUiPage.height

            PageHeader {
                id: header
                title: qsTr("openHAB Main UI")
            }

            WebView {
                id: webView
                width: parent.width
                height: mainUiPage.height - header.height
                url: settings.base_url
                active: true
            }
        }
    }
}
