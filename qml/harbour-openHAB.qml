import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "base"
import "base/utilities/SitemapLoader.js" as SitemapLoader

ApplicationWindow {
    id: appWindow

    Settings { id: settings }

    ListModel {
        id: availableSitemapModel
    }

    function loadAvailableSitemaps() {
        SitemapLoader.loadAvailableSitemaps(settings.base_url, availableSitemapModel)
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

    Component.onCompleted: {
        if (!_sitemapsLoaded) {
            loadAvailableSitemaps()
        }
        _ready = true
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
