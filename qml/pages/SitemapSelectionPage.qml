import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/SseEvents.js" as SseEvents

Page {
    id: sitemapSelectionPage
    allowedOrientations: Orientation.All

    signal sitemapSelected(string name, string label)

    property var sitemapModel: availableSitemapModel

    SilicaFlickable {
        id: flickableSelectionPage
        anchors.fill: parent
        contentHeight: contentColumn.height

        Column {
            id: contentColumn
            width: parent.width

            PageHeader {
                title: qsTr("Navigation")
            }

            // ── Main ────────────────────────────────────
            SectionHeader {
                text: qsTr("Main")
            }

            ListItem {
                id: homeItem
                contentHeight: Theme.itemSizeMedium

                onClicked: {
                    SseEvents.stopSSE(sseManager)
                    pageStack.animatorReplace(Qt.resolvedUrl("MainUiPage.qml"))
                }

                Row {
                    anchors {
                        fill: parent
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                    }
                    spacing: Theme.paddingMedium

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-home"
                        color: homeItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Home")
                        color: homeItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }
            }

            // ── Sitemaps ────────────────────────────────
            SectionHeader {
                text: qsTr("Sitemaps")
                visible: sitemapModel.count > 0
            }

            Repeater {
                model: sitemapModel

                ListItem {
                    id: sitemapItem
                    contentHeight: Theme.itemSizeMedium

                    onClicked: {
                        sitemapSelectionPage.sitemapSelected(model.name, model.label || model.name)
                        //pageStack.pop()
                    }

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }
                        spacing: Theme.paddingMedium

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-m-levels"
                            color: sitemapItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: model.label || model.name
                            color: sitemapItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeMedium
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }

            // ── System ──────────────────────────────────
            SectionHeader {
                text: qsTr("System")
            }

            ListItem {
                id: settingsItem
                contentHeight: Theme.itemSizeMedium

                onClicked: pageStack.animatorReplace(Qt.resolvedUrl("SettingsPage.qml"))

                Row {
                    anchors {
                        fill: parent
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                    }
                    spacing: Theme.paddingMedium

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-setting"
                        color: settingsItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Settings")
                        color: settingsItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }
            }

            ListItem {
                id: refreshItem
                contentHeight: Theme.itemSizeMedium

                onClicked: appWindow.loadAvailableSitemaps()

                Row {
                    anchors {
                        fill: parent
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                    }
                    spacing: Theme.paddingMedium

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-refresh"
                        color: refreshItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Refresh Sitemaps")
                        color: refreshItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }
            }

            // Bottom spacer
            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}

