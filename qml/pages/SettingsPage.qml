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

    function coverActionIconOptions() {
        return [
            { "name": "", "label": qsTr("Automatic") },
            { "name": "icon-cover-sync", "label": qsTr("Sync") },
            { "name": "icon-cover-refresh", "label": qsTr("Refresh") },
            { "name": "icon-cover-play", "label": qsTr("On") },
            { "name": "icon-cover-pause", "label": qsTr("Off") },
            { "name": "icon-cover-cancel", "label": qsTr("Stop") },
            { "name": "icon-cover-timer", "label": qsTr("Timer") },
            { "name": "icon-cover-favorite", "label": qsTr("Favorite") },
            { "name": "icon-cover-location", "label": qsTr("Location") },
            { "name": "icon-cover-new", "label": qsTr("New") }
        ]
    }

    // Results of the last "Test connection" (ConnectionManager result names).
    property string testLocalResult: ""
    property string testRemoteResult: ""

    function testResultText(result) {
        switch (result) {
        case "ok":           return qsTr("reachable")
        case "okNoCloud":    return qsTr("reachable, but not an openHAB Cloud (notifications will not be available)")
        case "network":      return qsTr("not reachable")
        case "unauthorized": return qsTr("login failed, check username and password")
        case "offline":      return qsTr("openHAB Cloud reachable, but your openHAB server is not connected to it")
        case "notOpenHab":   return qsTr("answers, but is not an openHAB server")
        case "skipped":      return qsTr("no URL entered")
        default:             return qsTr("request failed")
        }
    }

    Connections {
        target: connection
        onTestFinished: {
            settingspage.testLocalResult = localResult
            settingspage.testRemoteResult = remoteResult
        }
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

            // ── NFC ──────────────────────────────────────
            SectionHeader {
                text: qsTr("NFC")
            }

            TextSwitch {
                id: nfcEnabledField
                checked: settings.nfcEnabled && !demoModeField.checked
                // Greyed out without a reader and in demo mode.
                enabled: nfcManager.available && !demoModeField.checked
                text: qsTr("Detect NFC Actions")
                description: nfcManager.available
                             ? qsTr("Lay an openHAB tag on the phone to send its command. Works while the app is running, also from the cover.")
                             : qsTr("This device has no NFC reader.")
            }

            Label {
                visible: nfcEnabledField.enabled && nfcEnabledField.checked
                         && !nfcManager.systemEnabled
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.errorColor
                wrapMode: Text.Wrap
                // We only point at the system setting rather than flipping it ourselves
                text: qsTr("NFC is currently switched off in the system settings.")
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
                EnterKey.onClicked: usernameLocalField.focus = true
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

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: {
                    if (remoteEnabledField.checked) remoteUrlField.focus = true
                    else coverAction1Field.focus = true
                }
            }

            // ── Remote Server (openHAB Cloud) ────────────
            SectionHeader {
                text: qsTr("Remote server (openHAB Cloud)")
            }

            TextSwitch {
                id: remoteEnabledField
                checked: settings.remote_enabled && !demoModeField.checked
                // Demo mode is local-only.
                enabled: !demoModeField.checked
                text: qsTr("Use remote server")
                description: qsTr("Access openHAB from outside your home network, e.g. via myopenhab.org. The local server is still used whenever it is reachable.")
            }

            TextField {
                id: remoteUrlField
                visible: remoteEnabledField.checked
                width: parent.width
                label: qsTr("URL")
                placeholderText: "https://myopenhab.org"
                text: settings.remote_url
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: usernameRemoteField.focus = true
            }

            TextField {
                id: usernameRemoteField
                visible: remoteEnabledField.checked
                width: parent.width
                label: qsTr("Username")
                description: qsTr("E-mail address of your openHAB Cloud account.")
                placeholderText: qsTr("Enter username")
                text: settings.username_remote
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhEmailCharactersOnly

                EnterKey.enabled: true
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordRemoteField.focus = true
            }

            PasswordField {
                id: passwordRemoteField
                visible: remoteEnabledField.checked
                width: parent.width
                label: qsTr("Password")
                placeholderText: qsTr("Enter password")
                text: settings.decodePassword(settings.password_remote)

                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // ── Connection status & test ─────────────────
            Label {
                // Only meaningful once there is a choice to make.
                visible: connection.remoteConfigured
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
                text: qsTr("Currently: %1").arg(settings.connectionStatusText())
            }

            Item {
                width: 1
                height: Theme.paddingMedium
            }

            Button {
                id: testConnectionButton
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Test connection")
                enabled: !connection.testing && !demoModeField.checked
                onClicked: {
                    settingspage.testLocalResult = ""
                    settingspage.testRemoteResult = ""
                    // Tests what is in the fields right now, saved or not.
                    connection.testConnections(
                        settings.normalizeUrl(baseUrlField.text),
                        usernameLocalField.text, passwordLocalField.text,
                        remoteEnabledField.checked ? settings.normalizeUrl(remoteUrlField.text) : "",
                        usernameRemoteField.text.trim(), passwordRemoteField.text)
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Small
                running: connection.testing
                visible: running
            }

            Label {
                visible: settingspage.testLocalResult !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: settingspage.testLocalResult === "ok" ? Theme.highlightColor : Theme.errorColor
                wrapMode: Text.Wrap
                text: qsTr("Local server: %1").arg(settingspage.testResultText(settingspage.testLocalResult))
            }

            Label {
                visible: settingspage.testRemoteResult !== "" && settingspage.testRemoteResult !== "skipped"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: settingspage.testRemoteResult === "ok" ? Theme.highlightColor
                     : settingspage.testRemoteResult === "okNoCloud" ? Theme.secondaryHighlightColor
                     : Theme.errorColor
                wrapMode: Text.Wrap
                text: qsTr("Remote server: %1").arg(settingspage.testResultText(settingspage.testRemoteResult))
            }

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

            CoverActionIconComboBox {
                id: coverAction1IconField
                width: parent.width
                options: settingspage.coverActionIconOptions()
                iconName: settings.coverAction1_icon
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
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverItem1Field.focus = true
            }

            CoverActionIconComboBox {
                id: coverAction2IconField
                width: parent.width
                options: settingspage.coverActionIconOptions()
                iconName: settings.coverAction2_icon
            }

            // cover Item - displays one or two items with current state in cover
            SectionHeader {
                text: qsTr("Cover Items")
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
                text: qsTr("Configure Item-IDs for app cover display. Leave empty to do not display item states.")
            }

            TextField {
                id: coverItem1Field
                width: parent.width
                label: qsTr("Item-ID")
                placeholderText: qsTr("e.g. item_id1")
                text: settings.coverItem1

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverItem2Field.focus = true
            }

            TextField {
                id: coverItem2Field
                width: parent.width
                label: qsTr("Item-ID")
                placeholderText: qsTr("e.g. item_id2")
                text: settings.coverItem2

                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: coverItemRefreshTimeField.focus = true
            }

            TextField {
                id: coverItemRefreshTimeField
                width: parent.width
                label: qsTr("Cover item refresh time (milliseconds)")
                text: settings.coverItemRefreshTime
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1000; top: 3600000 }

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

                onClicked: Qt.openUrlExternally("https://community.openhab.org/c/apps-services/sailfishos/82")

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

                onClicked: Qt.openUrlExternally("https://crowdin.com/project/openhab-sailfishos")

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Add a translation")
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

                onClicked: Qt.openUrlExternally("https://www.openhabfoundation.org/privacy.html")

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Privacy Policy")
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

            // Demo mode wins: a tag pointing at demo server items is useless,
            // so listening is forced off there.
            settings.nfcEnabled = nfcEnabledField.checked && !settings.demoMode

            settings.remote_enabled = remoteEnabledField.checked && !settings.demoMode
            var remoteUrl = settings.normalizeUrl(remoteUrlField.text.trim())
            settings.remote_url = remoteUrl !== "" ? remoteUrl : "https://myopenhab.org"
            settings.username_remote = usernameRemoteField.text.trim()
            settings.password_remote = settings.encodePassword(passwordRemoteField.text)
            settings.coverAction1 = coverAction1Field.text
            settings.coverAction1_command = coverAction1CommandField.text
            settings.coverAction1_icon = coverAction1IconField.selectedIconName
            settings.coverAction2 = coverAction2Field.text
            settings.coverAction2_command = coverAction2CommandField.text
            settings.coverAction2_icon = coverAction2IconField.selectedIconName
            settings.coverItem1 = coverItem1Field.text
            settings.coverItem2 = coverItem2Field.text
            var refreshMs = parseInt(coverItemRefreshTimeField.text, 10)
            if (isNaN(refreshMs) || refreshMs < 1000)  refreshMs = 1000
            if (refreshMs > 3600000) refreshMs = 3600000
            settings.coverItemRefreshTime = refreshMs

            settings.username_local = usernameLocalField.text
            // Encode password as base64-obfuscated value before storing in dconf
            settings.password_local = settings.encodePassword(passwordLocalField.text)
        }
    }
}
