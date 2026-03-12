import QtQuick 2.0
import Nemo.Configuration 1.0

ConfigurationGroup {
    id: openHAB

    path: "/apps/openHAB"

    property bool demoMode: true
    property string lastVisitedPage: ""
    property string base_url: "https://demo.openhab.org"
    property bool openhab_cloud_service: false
    property string coverAction1: ""
    property string coverAction1_command: ""
    property string coverAction2: ""
    property string coverAction2_command: ""
}
