import QtQuick 2.0
import Sailfish.Silica 1.0

/**
 * "Hold the tag against the phone" -- the actual write.
 *
 * All wording lives here rather than in C++: the manager reports error codes,
 * QML turns them into sentences, which keeps every user visible string inside
 * qsTr() and therefore inside the Crowdin flow.
 */
Page {
    id: writePage
    allowedOrientations: Orientation.All

    /** Long form, written when it fits. */
    property string uri: ""
    /** Short fallback, used when the long one does not fit. */
    property string shortUri: ""
    /** What is being written, shown to the user for confirmation. */
    property string summary: ""

    property bool finished: false
    // Named writeOk, not success: inside onWriteFinished the signal parameter
    // would shadow a property called "success" and make the code ambiguous.
    property bool writeOk: false
    property string message: ""

    function messageForCode(code) {
        switch (code) {
        case "noTag":
            return qsTr("No tag was detected. Please try again.")
        case "unsupportedTagType":
            return qsTr("This tag type cannot be written.")
        case "readFailed":
            return qsTr("The tag could not be read. Hold it still against the phone.")
        case "tagTooSmall":
            return qsTr("The tag is too small for this command.")
        case "writeFailed":
            return qsTr("Writing failed. The tag may be write protected.")
        case "tagRemoved":
            return qsTr("The tag was removed too early. Its content may be incomplete.")
        case "cancelled":
            return qsTr("Cancelled.")
        default:
            return qsTr("Writing failed.")
        }
    }

    function start() {
        finished = false
        writeOk = false
        message = ""
        nfcManager.writeUri(uri, shortUri)
    }

    Component.onCompleted: {
        // Mute the reader for the whole time this page is open, not just while
        // the write is in flight: a tag read here would navigate the app away,
        // destroy this page, cancel the write and re-arm the reader -- with the
        // tag still on the phone, so it would loop.
        nfcManager.suspendReading()
        start()
    }

    // Leaving the page must not leave a write armed in the background --
    // it would grab the next tag the user lays down for something else.
    Component.onDestruction: {
        if (!finished) nfcManager.cancelWrite()
        nfcManager.resumeReading()
    }

    Connections {
        target: nfcManager
        onWriteFinished: {
            writePage.finished = true
            writePage.writeOk = success
            writePage.message = success
                    ? qsTr("Tag written.")
                    : writePage.messageForCode(errorCode)
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("Write NFC Tag") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: writePage.summary
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            // ── waiting ──
            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                visible: !writePage.finished

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Large
                    running: !writePage.finished
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Hold the tag against the back of the phone.")
                    color: Theme.secondaryHighlightColor
                }
            }

            // ── result ──
            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                visible: writePage.finished

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: writePage.writeOk ? "image://theme/icon-l-acknowledge"
                                              : "image://theme/icon-l-attention"
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: writePage.message
                    color: writePage.writeOk ? Theme.primaryColor
                                             : Theme.errorColor
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: writePage.writeOk ? qsTr("Done") : qsTr("Try again")
                    // Pop one level: back to the command list, where the user
                    // can pick another command or navigate on.
                    onClicked: writePage.writeOk ? pageStack.pop() : writePage.start()
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
