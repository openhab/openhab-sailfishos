import QtQuick 2.0
import Nemo.Configuration 1.0

ConfigurationGroup {
    id: openHAB

    path: "/apps/harbour-openHAB"

    property bool demoMode: true
    property string lastVisitedPage: "Stein"
    property string base_url: "http://10.10.0.20:8080"
    property bool openhab_cloud_service: true
    property string access_token: "oh.SailfishOSApp.tiKG9BK5xduN6fSIWrvy1WcmKJ87gFAW7ogk2NhmvT2CjTIcGpkxK0ldfXE2cQhhqbxnTZeZj1OwAbjTGLg"
}
