import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../components"

Dialog {
    id: settingspage

    Settings {
        id: settings
    }

    ListModel {
        id: availableSitemapModel
    }

    function loadAvailableSitemaps() {
        var url = settings.base_url + "/rest/sitemaps/"
        console.log("[SettingsPage] Loading sitemaps from: " + url)

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    availableSitemapModel.clear()

                    if (Array.isArray(data)) {
                        console.log("[SettingsPage] Found " + data.length + " sitemaps")
                        data.forEach(function(sitemap) {
                            availableSitemapModel.append({
                                name: sitemap.name,
                                label: sitemap.label || sitemap.name
                            })
                        })
                    }
                } catch (e) {
                    console.log("[SettingsPage] Error parsing sitemaps: " + e)
                }
            }
        }
        xhr.open("GET", url, true)
        xhr.send()
    }

    SilicaFlickable {
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
        }
        VerticalScrollDecorator {}
    }
    onDone: {
        if (result == DialogResult.Accepted) {
            settings.base_url = baseUrlField.text
            settings.openhab_cloud_service = openhabCloudServiceField.checked
            settings.demoMode = demoModeField.checked

            if (settings.demoMode && settings.base_url !== "https://demo.openhab.org") {
                console.log("demoMode == ON -- change base-url")
                settings.base_url = "https://demo.openhab.org"
                availableSitemapModel.clear()
                loadAvailableSitemaps()
            }
            else if (!settings.demoMode && settings.base_url !== "https://demo.openhab.org") {
                console.log("demoMode == OFF -- base-url changed")
                availableSitemapModel.clear()
                loadAvailableSitemaps()
            }
        }

    }
}
