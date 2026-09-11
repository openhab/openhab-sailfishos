import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "base"
import "components"
import "base/utilities/SitemapLoader.js" as SitemapLoader
import "base/utilities/NfcUri.js" as NfcUri
import "base/utilities/OpenHabApi.js" as OpenHabApi

ApplicationWindow {
    id: appWindow

    Settings { id: settings }

    // Single instance, reachable from everywhere -- same idea as `settings`.
    NotificationManager { id: notificationManager }

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

    // Track whether sitemaps were already loaded by a base_url change
    property bool _sitemapsLoaded: false

    // Guard: ignore base_url changes during initial property loading
    property bool _ready: false

    // Reload sitemaps and navigate to MainUI when base_url changes
    Connections {
        target: settings
        onBase_urlChanged: {
            if (!_ready) return
            console.log("[App] base_url changed to: " + settings.base_url + ", reloading sitemaps...")

            // Reset last visited page so the app doesn't try to load
            // an old sitemap that may not exist on the new server
            settings.lastVisitedPage = "MainUiPage"

            // Clear old sitemaps and load new ones
            availableSitemapModel.clear()
            loadAvailableSitemaps()
            _sitemapsLoaded = true

            // Delay navigation so the SettingsPage dialog-close animation
            // can finish first; avoids "cannot push while transition is in progress"
            _navigateToMainTimer.restart()
        }
    }

    Timer {
        id: _navigateToMainTimer
        interval: 600
        repeat: false
        onTriggered: {
            if (pageStack.busy) {
                // Page transition still running – try again shortly
                console.log("[App] PageStack busy, retrying navigation...")
                _navigateToMainTimer.restart()
                return
            }
            console.log("[App] Navigating to MainUiPage after base_url change")
            pageStack.clear()
            pageStack.push(mainUiPageComponent)
        }
    }

    initialPage: {
        console.log("[Start] settings.demoMode = " + settings.demoMode)
        console.log("[Start] settings.lastVisitedPage = " + settings.lastVisitedPage)

        if (settings.lastVisitedPage === "Sitemap") {
            return mainUiPageComponent
        }
        else if (settings.lastVisitedPage === "MainUiPage") {
            return mainUiPageComponent
        }
        else if (settings.lastVisitedPage !== "") {
            return sitemapPageComponent
        }
        else {
            return mainUiPageComponent
        }
    }

    // ════════════════════════════════════════════════
    //  NFC
    // ════════════════════════════════════════════════

    /**
     * Static per-type command table. Loaded once here because both the
     * NFC page and the sitemap context menu need it.
     *
     * Shipped as a plain file rather than inside ressources.qrc so it stays
     * adjustable on the device; a missing or broken file must therefore never
     * break the feature -- the command selection then falls back to free text.
     */
    property var nfcStaticCommands: ({})
    property var nfcReadOnlyTypes: []
    property bool nfcCommandTableLoaded: false

    function loadNfcCommandTable() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("base/data/item-commands.json"))
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            try {
                var json = JSON.parse(xhr.responseText)
                appWindow.nfcStaticCommands = json.commands || {}
                appWindow.nfcReadOnlyTypes = json.readOnlyTypes || []
            } catch (e) {
                console.warn("[NFC] item-commands.json unusable: " + e
                             + " - falling back to free text input")
                appWindow.nfcStaticCommands = {}
                appWindow.nfcReadOnlyTypes = []
            }
            appWindow.nfcCommandTableLoaded = true
        }
        xhr.send()
    }

    /**
     * Listening is tied to the settings switch alone -- deliberately NOT to
     * Qt.application.state. That means tags also work while the app is
     * only in the cover or fully in the background, which is what makes the
     * default-off switch the single brake the user has.
     */
    function syncNfcListening() {
        var shouldListen = nfcManager.available
                && settings.nfcEnabled
                && !settings.demoMode
        if (shouldListen && !nfcManager.listening) {
            console.log("[NFC] start listening")
            nfcManager.startListening()
        } else if (!shouldListen && nfcManager.listening) {
            console.log("[NFC] stop listening")
            nfcManager.stopListening()
        }
    }

    Connections {
        target: settings
        onNfcEnabledChanged: syncNfcListening()
        onDemoModeChanged: syncNfcListening()
    }

    Connections {
        target: nfcManager
        onAvailableChanged: syncNfcListening()
        onTagRead: appWindow.handleNfcTag(uri)
    }

    /** Entry point of the read path. `uri` is the raw openhab:// URI. */
    function handleNfcTag(uri) {
        var tag = NfcUri.parse(uri)
        if (!tag.valid) {
            // A foreign or unusable tag is ignored without bothering the user.
            // Device-id tags land here too: their state is a placeholder that
            // must never be sent.
            console.log("[Nfc] ignoring tag: " + tag.reason + " (" + uri + ")")
            return
        }
        if (tag.kind === "item") {
            _nfcRunItemCommand(tag)
        } else if (tag.kind === "sitemap") {
            _nfcOpenSitemap(tag)
        }
    }

    function _nfcDisplayName(tag) {
        // The label from the tag lets us name the item even when the server is
        // slow or unreachable -- that is what makes writing `l` worthwhile.
        return tag.label && tag.label !== "" ? tag.label : tag.item
    }

    function _nfcRunItemCommand(tag) {
        var name = _nfcDisplayName(tag)
        var shown = tag.mappedState && tag.mappedState !== ""
                ? tag.mappedState : tag.command

        // Check the item exists before sending, so a tag from another server
        // produces a clear message instead of a silent no-op.
        OpenHabApi.fetchItem(settings.apiConfig(), tag.item,
            function() {
                OpenHabApi.sendCommand(settings.apiConfig(), tag.item, tag.command,
                    function() {
                        // "sent", not "executed": a 200 only means openHAB
                        // accepted the command, not that the device reacted.
                        notificationManager.notifySuccess(
                            name + " → " + shown,
                            qsTr("Command sent to openHAB"))
                    },
                    function(error) {
                        notificationManager.notifyError(
                            qsTr("Command failed"),
                            name + " → " + shown + ": " + _nfcErrorText(error))
                    })
            },
            function(error) {
                notificationManager.notifyError(
                    qsTr("Command failed"),
                    error.kind === "notFound"
                        ? qsTr("Item \"%1\" does not exist on this server.").arg(tag.item)
                        : _nfcErrorText(error))
            })
    }

    function _nfcOpenSitemap(tag) {
        OpenHabApi.checkSitemapPath(settings.apiConfig(), tag.path,
            function() {
                var isSub = NfcUri.isSubPagePath(tag.path)
                // Navigate to whatever the tag points at, but persist only the
                // root sitemap: a subpage in lastVisitedPage would make every
                // cold start land there, permanently without SSE.
                var target = isSub
                        ? settings.base_url + "/rest/sitemaps" + tag.path
                        : tag.rootSitemap
                settings.lastVisitedPage = tag.rootSitemap

                // A sitemap tag says "show me this page", so bring the window
                // up front -- otherwise the navigation happens invisibly behind
                // the cover. Item tags deliberately do NOT do this: firing a
                // command should not steal the foreground.
                appWindow.activate()

                pageStack.clear()
                pageStack.push(Qt.resolvedUrl("pages/SitemapPage.qml"),
                               { "sitemapName": target })
            },
            function(error) {
                notificationManager.notifyError(
                    qsTr("Sitemap not opened"),
                    error.kind === "notFound"
                        ? qsTr("This sitemap does not exist on this server.")
                        : _nfcErrorText(error))
            })
    }

    /** Turns an OpenHabApi error object into a translated sentence. */
    function _nfcErrorText(error) {
        switch (error.kind) {
        case "network":      return qsTr("Server not reachable.")
        case "unauthorized": return qsTr("Not authorized. Check user name and password.")
        case "notFound":     return qsTr("Not found on this server.")
        case "server":       return qsTr("The server reported an error (%1).").arg(error.status)
        default:             return qsTr("Request failed (%1).").arg(error.status)
        }
    }

    Component.onCompleted: {
        if (!_sitemapsLoaded) {
            loadAvailableSitemaps()
        }
        _ready = true
        loadNfcCommandTable()
        syncNfcListening()
    }

    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    Component {
        id: mainUiPageComponent
        MainUiPage {}
    }

    Component {
        id: settingsPageComponent
        SettingsPage {}
    }

    Component {
        id: sitemapPageComponent
        SitemapPage {
            sitemapName: settings.lastVisitedPage
        }
    }
}
