import QtQuick 2.0
import Nemo.Configuration 1.0

ConfigurationGroup {
    id: openHAB

    path: "/apps/harbour-openhab"

    property bool demoMode: true
    property string lastVisitedPage: ""
    property string base_url: "https://demo.openhab.org"

    onDemoModeChanged: {
        if (demoMode) {
            console.log("[Settings] demoMode activated – setting base_url to demo server")
            base_url = "https://demo.openhab.org"
        }
    }

    // Normalize a URL string: fix single-slash protocol, strip trailing slashes
    function normalizeUrl(url) {
        // Fix "http:/" → "http://" and "https:/" → "https://"
        var singleSlashPattern = /^(https?):\/([^\/])/
        if (singleSlashPattern.test(url)) {
            url = url.replace(singleSlashPattern, "$1://$2")
        }
        // Remove trailing slashes
        while (url.length > 0 && url.charAt(url.length - 1) === '/') {
            url = url.substring(0, url.length - 1)
        }
        return url
    }

    property bool openhab_cloud_service: false
    property string coverAction1: ""
    property string coverAction1_command: ""
    property string coverAction2: ""
    property string coverAction2_command: ""
}
