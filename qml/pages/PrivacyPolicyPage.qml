import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

Page {
    id: privacyPolicyPage
    allowedOrientations: Orientation.All

    onStatusChanged: {
        if (status === PageStatus.Active) {
            webView.url = "https://www.openhabfoundation.org/privacy.html"
            webView.active = true
        } else if (status === PageStatus.Deactivating) {
            webView.active = false
        }
    }

    SilicaFlickable {
        anchors.fill: parent

        Column {
            id: column
            width: privacyPolicyPage.width
            height: privacyPolicyPage.height

            PageHeader {
                id: header
                title: qsTr("Privacy Policy")
            }

            WebView {
                id: webView
                width: parent.width
                height: privacyPolicyPage.height - header.height
                active: false
            }
        }
    }
}

