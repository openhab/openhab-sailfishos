import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "base"

ApplicationWindow {

    Settings { id: settings }

    initialPage: {
        console.log("[Start] settings.demoMode = " + settings.demoMode)
        console.log("[Start] settings.lastVisitedPage = " + settings.lastVisitedPage)
        if (settings.demoMode) {
            console.log("[Start] - demoMode == ON")
            settings.base_url = "https://demo.openhab.org"
            return mainUiPageComponent
        }
        else {
            if (settings.lastVisitedPage === "Sitemap") {
                //console.log("[Start] route - Sitemap")
                return mainUiPageComponent
            }
            else if (settings.lastVisitedPage === "MainUiPage") {
                //console.log("[Start] route - MainUiPage")
                return mainUiPageComponent
            }
            else if (settings.lastVisitedPage !== "") {
                //console.log("[Start] route - lastVisitedPage ist befüllt.")
                return sitemapPageComponent
            }
            else {
                // Fallback: load DemoSitemap if nothing else is available
                //console.log("[Start] route - fallback")
                return mainUiPageComponent
            }
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
