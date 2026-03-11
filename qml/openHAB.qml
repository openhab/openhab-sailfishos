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

    // Reload sitemaps when base_url changes
    Connections {
        target: settings
        onBase_urlChanged: {
            console.log("[App] base_url changed to: " + settings.base_url + ", reloading sitemaps...")
            loadAvailableSitemaps()
            _sitemapsLoaded = true
        }
    }

    initialPage: {
        console.log("[Start] settings.demoMode = " + settings.demoMode)
        console.log("[Start] settings.lastVisitedPage = " + settings.lastVisitedPage)
        if (settings.demoMode) {
            console.log("[Start] - demoMode == ON")
            settings.base_url = "https://demo.openhab.org"
            // loadAvailableSitemaps will be triggered by onBase_urlChanged
        }

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
