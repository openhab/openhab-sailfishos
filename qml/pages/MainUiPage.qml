import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import "../base"

Page {
    id: mainUiPage
    allowedOrientations: Orientation.All

    Settings { id: settings }

    Component.onCompleted: {
        console.log("[MainUiPage] loaded")
        settings.lastVisitedPage = "MainUiPage"
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            webView.url = settings.base_url
            webView.active = true
        } else if (status === PageStatus.Deactivating) {
            webView.active = false
        }
    }

    // Toolbar header with navigation icons
    Item {
        id: toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.itemSizeMedium

        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
        }

        Label {
            id: titleLabel
            text: qsTr("openHAB Main UI")
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: menuButton.left
                rightMargin: Theme.paddingMedium
            }
            horizontalAlignment: Text.AlignLeft
            truncationMode: TruncationMode.Fade
        }

        // Sitemap/Navigation menu button
        IconButton {
            id: menuButton
            icon.source: "image://theme/icon-m-menu"
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
            }
            onClicked: {
                var page = pageStack.animatorPush(Qt.resolvedUrl("SitemapSelectionPage.qml"))
                page.pageCompleted.connect(function(selPage) {
                    selPage.sitemapSelected.connect(function(name, label) {
                        settings.lastVisitedPage = name
                        console.log("[MainUiPage] Sitemap selected: " + settings.lastVisitedPage)
                        pageStack.animatorReplace(Qt.resolvedUrl("SitemapPage.qml"), {
                            "sitemapName": name,
                            "pageTitle": label
                        })
                    })
                })
            }
        }
    }

    WebView {
        id: webView
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        url: settings.base_url
        active: false
    }
}
