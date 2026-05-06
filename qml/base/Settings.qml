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
    property string username_local: ""
    // Stored as base64-obfuscated string (prefix "b64:") to prevent plain-text
    // visibility in the dconf database (~/.config). Not cryptographically secure,
    // but prevents casual read-out from config files.
    property string password_local: ""

    // Encodes a plain-text password for storage in dconf.
    function encodePassword(plain) {
        if (!plain || plain === "") return ""
        try {
            return "b64:" + Qt.btoa(plain)
        } catch(e) {
            console.warn("[Settings] encodePassword failed: " + e)
            return plain
        }
    }

    // Decodes a stored password value back to plain text.
    // Falls back to the raw value for migration compatibility (old plain-text entries).
    function decodePassword(enc) {
        if (!enc || enc === "") return ""
        if (enc.indexOf("b64:") !== 0) return enc   // plain-text fallback (migration)
        try {
            return Qt.atob(enc.substring(4))
        } catch(e) {
            console.warn("[Settings] decodePassword failed: " + e)
            return ""
        }
    }
}
