import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base"
import "../base/utilities/OpenHabApi.js" as OpenHabApi

/**
 * Entry point of the NFC feature: pick the item whose command should go onto
 * a tag.
 *
 * Item source: the items of the last opened sitemap by default, the full
 * item list behind a pulley entry. "All items the server
 * accepts commands for" is not a query openHAB offers -- GET /rest/items
 * returns everything, groups included, easily several hundred entries.
 */
Page {
    id: nfcPage
    allowedOrientations: Orientation.All

    Settings { id: settings }

    /** false: items of the last sitemap. true: every item on the server. */
    property bool showAllItems: false
    property bool loading: false
    property string errorText: ""
    property string filter: ""

    // Static per-type command table, loaded once in the ApplicationWindow.
    readonly property var staticCommands: appWindow.nfcStaticCommands
    readonly property var readOnlyTypes: appWindow.nfcReadOnlyTypes

    ListModel { id: itemModel }

    // ── loading items ──────────────────────────────────────────────────
    function reload() {
        itemModel.clear()
        errorText = ""
        loading = true
        if (showAllItems) {
            loadAllItems()
        } else {
            loadSitemapItems()
        }
    }

    function currentSitemapName() {
        var page = settings.lastVisitedPage
        if (!page || page === "" || page === "MainUiPage" || page === "Sitemap") {
            return ""
        }
        // Subpages are stored as full URLs; those have no sitemap name here.
        if (page.indexOf("http") === 0) return ""
        return page
    }

    function loadSitemapItems() {
        var name = currentSitemapName()
        if (name === "") {
            loading = false
            errorText = qsTr("Open a sitemap first, or show all items from the pulley menu.")
            return
        }
        var xhr = new XMLHttpRequest()
        xhr.open("GET", settings.base_url + "/rest/sitemaps/" + name, true)
        xhr.setRequestHeader("Accept", "application/json")
        var auth = OpenHabApi.authHeader(settings.apiConfig())
        if (auth) xhr.setRequestHeader("Authorization", auth)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            loading = false
            if (xhr.status < 200 || xhr.status >= 300) {
                errorText = OpenHabApi.classifyError(xhr).message
                return
            }
            try {
                var items = OpenHabApi.collectSitemapItems(
                            JSON.parse(xhr.responseText), readOnlyTypes)
                fillModel(items)
                if (items.length === 0) {
                    errorText = qsTr("This sitemap has no items that accept commands.")
                }
            } catch (e) {
                errorText = qsTr("Could not read the sitemap.")
                console.warn("[NfcPage] " + e)
            }
        }
        xhr.send()
    }

    function loadAllItems() {
        OpenHabApi.fetchItems(settings.apiConfig(),
            function(json) {
                loading = false
                fillModel(OpenHabApi.filterCommandableItems(json, readOnlyTypes))
            },
            function(error) {
                loading = false
                errorText = error.message
            })
    }

    function fillModel(items) {
        for (var i = 0; i < items.length; i++) {
            itemModel.append({
                "itemName": items[i].name,
                "itemLabel": items[i].label,
                "itemType": items[i].type,
                "mappingsJson": JSON.stringify(items[i].mappings || []),
                "commandJson": JSON.stringify(items[i].commandDescription || null)
            })
        }
    }

    function matchesFilter(name, label) {
        if (filter === "") return true
        var needle = filter.toLowerCase()
        return name.toLowerCase().indexOf(needle) >= 0
                || label.toLowerCase().indexOf(needle) >= 0
    }

    // The table load is fired once at app start; if it is still running, wait
    // for it so the command selection is never built from an empty table.
    Component.onCompleted: {
        // The user came here to write a tag; reacting to one that is laid on
        // the reader would throw them out of the flow.
        nfcManager.suspendReading()
        if (appWindow.nfcCommandTableLoaded) {
            reload()
        }
    }

    Component.onDestruction: nfcManager.resumeReading()

    Connections {
        target: appWindow
        onNfcCommandTableLoadedChanged: {
            if (appWindow.nfcCommandTableLoaded) nfcPage.reload()
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: itemModel

        PullDownMenu {
            MenuItem {
                text: nfcPage.showAllItems ? qsTr("Show sitemap items")
                                           : qsTr("Show all items")
                onClicked: {
                    nfcPage.filter = ""
                    nfcPage.showAllItems = !nfcPage.showAllItems
                    nfcPage.reload()
                }
            }
            MenuItem {
                text: qsTr("Reload")
                onClicked: nfcPage.reload()
            }
        }

        header: Column {
            width: listView.width

            PageHeader {
                title: qsTr("Write NFC Tag")
                description: nfcPage.showAllItems
                             ? qsTr("All items")
                             : qsTr("Sitemap %1").arg(nfcPage.currentSitemapName())
            }

            // Status of the NFC hardware. Without this the user would have no
            // idea why writing does nothing.
            Label {
                visible: !nfcManager.available || !nfcManager.systemEnabled
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: !nfcManager.available
                      ? qsTr("This device has no NFC reader.")
                      : qsTr("NFC is switched off. Enable it in the system settings.")
            }

            SearchField {
                visible: nfcPage.showAllItems
                width: parent.width
                placeholderText: qsTr("Search item")
                onTextChanged: nfcPage.filter = text.trim()
            }

            Label {
                visible: nfcPage.errorText !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: nfcPage.errorText
            }
        }

        delegate: ListItem {
            id: itemDelegate
            contentHeight: Theme.itemSizeMedium
            visible: nfcPage.matchesFilter(model.itemName, model.itemLabel)
            height: visible ? contentHeight : 0

            onClicked: pageStack.animatorPush(Qt.resolvedUrl("NfcCommandPage.qml"), {
                "itemName": model.itemName,
                "itemLabel": model.itemLabel,
                "itemType": model.itemType,
                "mappingsJson": model.mappingsJson,
                "commandJson": model.commandJson,
                "staticCommands": nfcPage.staticCommands
            })

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: model.itemLabel
                    truncationMode: TruncationMode.Fade
                    color: itemDelegate.highlighted ? Theme.highlightColor
                                                    : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: model.itemName + "  ·  " + model.itemType
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: itemDelegate.highlighted ? Theme.secondaryHighlightColor
                                                    : Theme.secondaryColor
                }
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: nfcPage.loading
        }

        ViewPlaceholder {
            enabled: !nfcPage.loading && itemModel.count === 0
                     && nfcPage.errorText === ""
            text: qsTr("No items")
        }

        VerticalScrollDecorator {}
    }
}
