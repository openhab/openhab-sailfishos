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
        SitemapLoader.loadAvailableSitemaps(
            settings.base_url, availableSitemapModel,
            undefined, undefined,
            settings.username_local,
            settings.decodePassword(settings.password_local)
        )
    }

    Component.onCompleted: { }

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
                placeholderText: qsTr("https://demo.openhab.org")
                text: settings.base_url
                inputMethodHints: Qt.ImhUrlCharactersOnly

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            TextField {
                id: usernameLocalField
                width: parent.width
                label: qsTr("Username")
                description: qsTr("OPTIONAL: Server username – leave empty to send no credentials.")
                placeholderText: qsTr("Enter username")
                text: settings.username_local
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

                EnterKey.enabled: true
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordLocalField.focus = true
            }

            PasswordField {
                id: passwordLocalField
                width: parent.width
                label: qsTr("Password")
                description: qsTr("OPTIONAL: Server password – leave empty to send no credentials.")
                placeholderText: qsTr("Enter password")
                // Decode the base64-obfuscated value stored in settings
                text: settings.decodePassword(settings.password_local)

                EnterKey.iconSource: "image://theme/icon-m-enter-close"
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
                placeholderText: qsTr("e.g. item_id1")
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
                placeholderText: qsTr("e.g. item_id1")
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

            // ── About ────────────────────────────────────
            SectionHeader {
                text: qsTr("About")
            }

            ListItem {
                contentHeight: Theme.itemSizeMedium
                _backgroundColor: "transparent"
                highlighted: false

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("App Version")
                    color: Theme.primaryColor
                }
                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.application.version !== "" ? Qt.application.version : "?.?.?"
                    color: Theme.secondaryColor
                }
            }

            Separator {
                width: parent.width
                color: Theme.primaryColor
                horizontalAlignment: Qt.AlignHCenter
            }

            ListItem {
                contentHeight: Theme.itemSizeMedium

                onClicked: Qt.openUrlExternally("https://community.openhab.org/")

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Report a bug or request a feature")
                    color: Theme.primaryColor
                }
                Image {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-right"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                }
            }

            Separator {
                width: parent.width
                color: Theme.primaryColor
                horizontalAlignment: Qt.AlignHCenter
            }

            ListItem {
                contentHeight: Theme.itemSizeMedium

                onClicked: pageStack.push(Qt.resolvedUrl("LegalPage.qml"))

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Legal")
                    color: Theme.primaryColor
                }
                Image {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-right"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                }
            }

            Separator {
                width: parent.width
                color: Theme.primaryColor
                horizontalAlignment: Qt.AlignHCenter
            }

            ListItem {
                contentHeight: Theme.itemSizeMedium

                onClicked: pageStack.push(Qt.resolvedUrl("PrivacyPolicyPage.qml"))

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Privacy Policy")
                    color: Theme.highlightColor
                }
                Image {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-right"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                }
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
            // Save demoMode first – the onDemoModeChanged handler in
            // Settings.qml will automatically set base_url to the demo
            // server when demoMode is switched on.
            settings.demoMode = demoModeField.checked

            // Only apply the manually entered URL when demoMode is off;
            // otherwise the demo URL set by onDemoModeChanged must stay.
            if (!settings.demoMode) {
                settings.base_url = settings.normalizeUrl(baseUrlField.text)
            }

            //settings.openhab_cloud_service = openhabCloudServiceField.checked
            settings.coverAction1 = coverAction1Field.text
            settings.coverAction1_command = coverAction1CommandField.text
            settings.coverAction2 = coverAction2Field.text
            settings.coverAction2_command = coverAction2CommandField.text

            settings.username_local = usernameLocalField.text
            // Encode password as base64-obfuscated value before storing in dconf
            settings.password_local = settings.encodePassword(passwordLocalField.text)
        }
    }
}
