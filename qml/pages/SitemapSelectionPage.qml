import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"

Page {
    id: sitemapSelectionPage
    allowedOrientations: Orientation.All

    signal sitemapSelected(string name, string label)

    property var sitemapModel: availableSitemapModel

    SilicaListView {
        id: listView
        anchors.fill: parent

        header: Column {
            width: parent.width

            PageHeader {
                title: qsTr("Navigation")
            }
        }

        model: ListModel {
            id: combinedModel
        }

        delegate: ListItem {
            id: listItem
            contentHeight: Theme.itemSizeMedium
            width: listView.width

            onClicked: {
                if (model.action === "main") {
                    pageStack.animatorReplace(Qt.resolvedUrl("MainUiPage.qml"))
                } else if (model.action === "settings") {
                    pageStack.animatorReplace(Qt.resolvedUrl("SettingsPage.qml"))
                } else if (model.action === "refresh") {
                    appWindow.loadAvailableSitemaps()
                    rebuildModel()
                } else if (model.action === "sitemap") {
                    sitemapSelectionPage.sitemapSelected(model.name, model.label)
                    pageStack.pop()
                }
            }

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingMedium

                Icon {
                    id: itemIcon
                    anchors.verticalCenter: parent.verticalCenter
                    source: model.icon || ""
                    color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    visible: source != ""
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (itemIcon.visible ? itemIcon.width + parent.spacing : 0)
                    text: model.label || ""
                    color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        section {
            property: "section"
            delegate: SectionHeader {
                text: section
            }
        }
    }

    function rebuildModel() {
        combinedModel.clear()

        // Navigation section
        combinedModel.append({
            "label": qsTr("Home"),
            "icon": "image://theme/icon-m-home",
            "action": "main",
            "name": "",
            "section": qsTr("Main")
        })

        // Sitemaps section
        for (var i = 0; i < sitemapModel.count; i++) {
            var item = sitemapModel.get(i)
            combinedModel.append({
                "label": item.label || item.name,
                "icon": "image://theme/icon-m-levels",
                "action": "sitemap",
                "name": item.name,
                "section": qsTr("Sitemaps")
            })
        }

        // Actions section
        combinedModel.append({
            "label": qsTr("Settings"),
            "icon": "image://theme/icon-m-setting",
            "action": "settings",
            "name": "",
            "section": qsTr("System")
        })

        combinedModel.append({
            "label": qsTr("Refresh Sitemaps"),
            "icon": "image://theme/icon-m-refresh",
            "action": "refresh",
            "name": "",
            "section": qsTr("System")
        })
    }

    Component.onCompleted: {
        rebuildModel()
    }
}

