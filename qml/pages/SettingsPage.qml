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
        Column {
            anchors.fill: parent
            DialogHeader {
                acceptText: qsTr("Save")
            }
            TextSwitch {
                id: demoModeField
                checked: settings.demoMode
                text: qsTr("Demo Mode")
                description: qsTr("If selected, Demo SiteMaps and DemoPages will be shown.")
            }

            TextField {
                id: baseUrlField
                width: parent.width
                label: qsTr("OpenHAB base URL")
                placeholderText: qsTr("http://example.com:8080")
                text: settings.base_url
                focus: true
                inputMethodHints: Qt.ImhUrlCharactersOnly

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }
            TextSwitch {
                id: openhabCloudServiceField
                checked: settings.openhab_cloud_service
                text: qsTr("openHAB Cloud Service")
                description: qsTr("If selected, Notifications from openHAB Cloud Service can be received.")
            }
            TextField {
                id: coverAction1Field
                width: parent.width
                label: qsTr("Cover Action - Left Button")
                placeholderText: qsTr("")
                text: settings.coverAction1
                description: qsTr("Item-Id from OpenHAB for left cover action. If empty, no action will be shown.")
                focus: true
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }
            TextField {
                id: coverAction1CommandField
                width: parent.width
                label: qsTr("Cover Action Command - Left Button")
                placeholderText: qsTr("")
                text: settings.coverAction1_command
                description: qsTr("Command for the item, which is linked to Cover Action Left Button. If empty, no action will be shown.")
                focus: true
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }
            TextField {
                id: coverAction2Field
                width: parent.width
                label: qsTr("Cover Action - Right Button")
                placeholderText: qsTr("")
                text: settings.coverAction2
                description: qsTr("Item-Id from OpenHAB for right cover action. If empty, no action will be shown.")
                focus: true
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }
            TextField {
                id: coverAction2CommandField
                width: parent.width
                label: qsTr("Cover Action Command - Right Button")
                placeholderText: qsTr("")
                text: settings.coverAction2_command
                description: qsTr("Command for the item, which is linked to Cover Action right Button. If empty, no action will be shown.")
                focus: true
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
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
