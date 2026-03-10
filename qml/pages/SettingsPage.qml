import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../components"
import "../base/utilities/SitemapLoader.js" as SitemapLoader

Dialog {
    id: settingspage

    Settings {
        id: settings
    }

    ListModel {
        id: availableSitemapModel
    }

    function loadAvailableSitemaps() {
        SitemapLoader.loadAvailableSitemaps(settings.base_url, availableSitemapModel)
    }

    Component.onCompleted: {
        //loadAvailableSitemaps()
    }

    SilicaFlickable {
        id: settingsPage
        anchors.fill: parent
        contentHeight: contentColumn.height

        Column {
            id: contentColumn
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("Settings")
            }

            // ── General ──────────────────────────────────
            SectionHeader {
                text: qsTr("General")
            }

            TextSwitch {
                id: demoModeField
                checked: settings.demoMode
                text: qsTr("Demo Mode")
                description: qsTr("If selected, Demo SiteMaps and DemoPages will be shown.")
            }

            // ── Local Server ─────────────────────────────
            SectionHeader {
                text: qsTr("Local server")
            }

            TextField {
                id: baseUrlField
                width: parent.width
                label: qsTr("URL")
                placeholderText: qsTr("http://example.com:8080")
                text: settings.base_url
                inputMethodHints: Qt.ImhUrlCharactersOnly

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            // ── Cloud Service ────────────────────────────
            //SectionHeader {
            //    text: qsTr("Remote server")
            //}

            //TextSwitch {
            //    id: openhabCloudServiceField
            //    checked: settings.openhab_cloud_service
            //    text: qsTr("openHAB Cloud Service")
            //    description: qsTr("If selected, Notifications from openHAB Cloud Service can be received.")
            //}

            // ── Cover Actions ────────────────────────────
            SectionHeader {
                text: qsTr("Cover actions")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
                text: qsTr("Configure Item-IDs and commands for the app cover quick actions. Leave empty to hide an action.")
            }

            // Left cover action
            SectionHeader {
                text: qsTr("Left button")
                font.pixelSize: Theme.fontSizeSmall
            }

            TextField {
                id: coverAction1Field
                width: parent.width
                label: qsTr("Item-ID")
                placeholderText: qsTr("e.g. Shelly_buero_lampe")
                text: settings.coverAction1

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverAction1CommandField.focus = true
            }

            TextField {
                id: coverAction1CommandField
                width: parent.width
                label: qsTr("Command")
                placeholderText: qsTr("e.g. ON, OFF, TOGGLE")
                text: settings.coverAction1_command

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverAction2Field.focus = true
            }

            // Right cover action
            SectionHeader {
                text: qsTr("Right button")
                font.pixelSize: Theme.fontSizeSmall
            }

            TextField {
                id: coverAction2Field
                width: parent.width
                label: qsTr("Item-ID")
                placeholderText: qsTr("e.g. Shelly_buero_lampe")
                text: settings.coverAction2

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverAction2CommandField.focus = true
            }

            TextField {
                id: coverAction2CommandField
                width: parent.width
                label: qsTr("Command")
                placeholderText: qsTr("e.g. ON, OFF, TOGGLE")
                text: settings.coverAction2_command

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // Bottom spacer
            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}

        PushUpMenu {
            MenuItem {
                text: qsTr("Scroll to top")
                onClicked: settingsPage.scrollToTop()
            }
        }
    }
    onDone: {
        if (result == DialogResult.Accepted) {
            settings.base_url = baseUrlField.text
            settings.openhab_cloud_service = openhabCloudServiceField.checked
            settings.demoMode = demoModeField.checked
            settings.coverAction1 = coverAction1Field.text
            settings.coverAction1_command = coverAction1CommandField.text
            settings.coverAction2 = coverAction2Field.text
            settings.coverAction2_command = coverAction2CommandField.text

            if (settings.demoMode && settings.base_url !== "https://demo.openhab.org") {
                console.log("demoMode == ON -- change base-url")
                settings.base_url = "https://demo.openhab.org"
                //availableSitemapModel.clear()
                //loadAvailableSitemaps()
            }
            else if (!settings.demoMode && settings.base_url !== "https://demo.openhab.org") {
                console.log("demoMode == OFF -- base-url changed")
                //availableSitemapModel.clear()
                //loadAvailableSitemaps()
            }
        }

    }
}
