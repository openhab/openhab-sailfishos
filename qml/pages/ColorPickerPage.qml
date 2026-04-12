import QtQuick 2.0
import Sailfish.Silica 1.0
import "../base/utilities/ColorUtils.js" as ColorUtils

// ════════════════════════════════════════════════════════════════════════
// ColorPickerPage – HSB color picker for openHAB Color items
//
// Layout (top → bottom, scrollable):
//   1. Color preview bar           – shows the currently selected color
//   2. Hue strip                   – horizontal rainbow bar, tap/drag to pick hue
//   3. Saturation-Value picker     – 2-D canvas (white→hue × bright→black)
//   4. Brightness slider           – Silica Slider for fine adjustment
//   5. Preset color grid           – quick-select from common colors
//
// Commands are sent automatically (debounced) as the user interacts.
// ════════════════════════════════════════════════════════════════════════

Page {
    id: colorPickerPage
    allowedOrientations: Orientation.All

    // ── Properties passed from SitemapPage ──
    property string itemName: ""
    property string itemLabel: ""
    property real   initialHue: 0
    property real   initialSaturation: 100
    property real   initialBrightness: 100
    property string baseUrl: ""

    // ── Current editable HSB values ──
    property real currentHue:        initialHue
    property real currentSaturation: initialSaturation
    property real currentBrightness: initialBrightness

    // ── Guard: suppress auto-send until Component.onCompleted finishes ──
    property bool _ready: false

    // ── Derived current color ──
    readonly property color currentColor:
        ColorUtils.hsbToColor(currentHue, currentSaturation, currentBrightness)

    // ── Keep brightness slider in sync when SV picker changes brightness ──
    // Deferred to the next event-loop iteration to avoid re-entrancy with
    // Slider's internal signal processing.
    Timer {
        id: sliderSyncTimer
        interval: 1
        onTriggered: brightnessSlider.value = currentBrightness
    }

    // ── Deferred send timer ──────────────────────────────────────────
    // Calling colorChanged() (or sendTimer.restart()) synchronously inside
    // Slider signal handlers (onPressedChanged / onValueChanged) or
    // Repeater-delegate onClicked causes the QML engine to silently abort
    // the running handler due to re-entrant signal processing.
    // This 5 ms timer breaks the synchronous chain so the send always fires.
    Timer {
        id: deferredSendTimer
        interval: 5
        onTriggered: colorChanged()
    }

    // ── React to ANY HSB property change (auto-triggers deferred send) ──
    onCurrentHueChanged:        { if (_ready) deferredSendTimer.restart(); }
    onCurrentSaturationChanged: { if (_ready) deferredSendTimer.restart(); }
    onCurrentBrightnessChanged: {
        if (!brightnessSlider.pressed) {
            sliderSyncTimer.restart();
        }
        if (_ready) deferredSendTimer.restart();
    }

    // ── Debounce timer – sends HSB command 300 ms after last interaction ──
    Timer {
        id: sendTimer
        interval: 300
        onTriggered: {
            if (itemName === "") return;
            var cmd = Math.round(currentHue) + ","
                    + Math.round(currentSaturation) + ","
                    + Math.round(currentBrightness);
            console.log("[ColorPicker] Sending command: " + cmd + " to " + itemName);
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    console.log("[ColorPicker] Response: " + xhr.status);
                }
            };
            xhr.open("POST", baseUrl + "/rest/items/" + itemName, true);
            xhr.setRequestHeader("Content-Type", "text/plain");
            xhr.send(cmd);
        }
    }

    function colorChanged() {
        console.log("[ColorPicker] colorChanged → scheduling send (H=" + Math.round(currentHue)
                    + " S=" + Math.round(currentSaturation) + " B=" + Math.round(currentBrightness) + ")");
        sendTimer.restart();
    }

    // ════════════════════════════════════════════════════════════════════
    // UI
    // ════════════════════════════════════════════════════════════════════

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height + Theme.paddingLarge * 2

        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: itemLabel || qsTr("Color Picker") }

            // ── 1. Color Preview ─────────────────────────────────────
            Rectangle {
                id: colorPreview
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: Theme.itemSizeLarge
                radius: Theme.paddingMedium
                color: currentColor
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor, 0.3)

                Label {
                    anchors.centerIn: parent
                    text: "H " + Math.round(currentHue) + "°  S " + Math.round(currentSaturation) + "%  B " + Math.round(currentBrightness) + "%"
                    color: currentBrightness > 50 && currentSaturation < 60 ? "#000000" : "#FFFFFF"
                    font.pixelSize: Theme.fontSizeSmall
                    style: Text.Outline
                    styleColor: currentBrightness > 50 && currentSaturation < 60
                                ? Qt.rgba(1, 1, 1, 0.25)
                                : Qt.rgba(0, 0, 0, 0.4)
                }
            }

            // ── 2. Hue Strip ─────────────────────────────────────────
            Item {
                id: hueContainer
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: Theme.itemSizeExtraSmall

                Canvas {
                    id: hueCanvas
                    anchors.fill: parent

                    onPaint: {
                        var ctx = getContext("2d");
                        var w = width;
                        var h = height;

                        var grad = ctx.createLinearGradient(0, 0, w, 0);
                        grad.addColorStop(0,     "#FF0000");
                        grad.addColorStop(1/6,   "#FFFF00");
                        grad.addColorStop(2/6,   "#00FF00");
                        grad.addColorStop(3/6,   "#00FFFF");
                        grad.addColorStop(4/6,   "#0000FF");
                        grad.addColorStop(5/6,   "#FF00FF");
                        grad.addColorStop(1,     "#FF0000");
                        ctx.fillStyle = grad;
                        ctx.fillRect(0, 0, w, h);
                    }
                }

                // Thin border overlay
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.rgba(Theme.primaryColor, 0.15)
                }

                // Hue indicator
                Rectangle {
                    id: hueIndicator
                    width: Theme.paddingLarge
                    height: parent.height + Theme.paddingSmall * 2
                    y: -Theme.paddingSmall
                    x: Math.max(0, Math.min(parent.width - width,
                       (currentHue / 360) * parent.width - width / 2))
                    radius: Theme.paddingSmall / 2
                    color: "transparent"
                    border.width: 3
                    border.color: "white"

                    // Dark outline for contrast
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        radius: parent.radius + 1
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.35)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -Theme.paddingMedium
                    anchors.bottomMargin: -Theme.paddingMedium

                    function updateHue(mx) {
                        var localX = Math.max(0, Math.min(hueCanvas.width, mx));
                        currentHue = (localX / hueCanvas.width) * 360;
                        svCanvas.requestPaint();
                    }

                    onPressed: updateHue(mouseX)
                    onPositionChanged: updateHue(mouseX)
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                text: qsTr("Hue")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            // ── 3. Saturation-Value Picker ───────────────────────────
            Item {
                id: svContainer
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: width * 0.55

                Canvas {
                    id: svCanvas
                    anchors.fill: parent

                    property real canvasHue: currentHue
                    onCanvasHueChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var w = width;
                        var h = height;

                        // Layer 1: horizontal white → pure hue color (saturation)
                        var hueColor = ColorUtils.hsbToCss(canvasHue, 100, 100);
                        var grad1 = ctx.createLinearGradient(0, 0, w, 0);
                        grad1.addColorStop(0, "#FFFFFF");
                        grad1.addColorStop(1, hueColor);
                        ctx.fillStyle = grad1;
                        ctx.fillRect(0, 0, w, h);

                        // Layer 2: vertical transparent → black (brightness)
                        var grad2 = ctx.createLinearGradient(0, 0, 0, h);
                        grad2.addColorStop(0, "rgba(0,0,0,0)");
                        grad2.addColorStop(1, "rgba(0,0,0,1)");
                        ctx.fillStyle = grad2;
                        ctx.fillRect(0, 0, w, h);
                    }
                }

                // Thin border overlay
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.rgba(Theme.primaryColor, 0.15)
                }

                // SV cursor – white circle with dark outline
                Rectangle {
                    id: svCursor
                    width: 22
                    height: 22
                    radius: 11
                    color: "transparent"
                    border.width: 3
                    border.color: "white"
                    x: Math.max(0, Math.min(parent.width - width,
                       (currentSaturation / 100) * parent.width - width / 2))
                    y: Math.max(0, Math.min(parent.height - height,
                       (1 - currentBrightness / 100) * parent.height - height / 2))

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }

                MouseArea {
                    anchors.fill: parent

                    function updateSV(mx, my) {
                        var localX = Math.max(0, Math.min(svCanvas.width, mx));
                        var localY = Math.max(0, Math.min(svCanvas.height, my));
                        currentSaturation = (localX / svCanvas.width) * 100;
                        currentBrightness = (1 - localY / svCanvas.height) * 100;
                    }

                    onPressed: updateSV(mouseX, mouseY)
                    onPositionChanged: updateSV(mouseX, mouseY)
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge

                Label {
                    text: qsTr("Saturation") + ": " + Math.round(currentSaturation) + "%"
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    text: qsTr("Brightness") + ": " + Math.round(currentBrightness) + "%"
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ── 4. Brightness Slider ─────────────────────────────────
            Slider {
                id: brightnessSlider
                width: parent.width
                minimumValue: 0
                maximumValue: 100
                value: initialBrightness
                stepSize: 1
                label: qsTr("Brightness")
                valueText: Math.round(value) + "%"

                // Live updates while dragging
                onValueChanged: {
                    if (pressed) {
                        currentBrightness = value;
                    }
                }

                // Reliable release detection via pressedChanged
                onPressedChanged: {
                    if (!pressed) {
                        console.log("[ColorPicker] Brightness slider released: " + value);
                        currentBrightness = value;
                    }
                }
            }

            // ── 5. Preset Colors ─────────────────────────────────────
            Label {
                x: Theme.horizontalPageMargin
                text: qsTr("Preset Colors")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Grid {
                id: presetGrid
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                columns: 7
                spacing: Theme.paddingSmall

                property real cellSize: (width - spacing * (columns - 1)) / columns

                Repeater {
                    model: ListModel { id: presetModel }

                    Rectangle {
                        id: presetCell
                        width: presetGrid.cellSize
                        height: presetGrid.cellSize
                        radius: Theme.paddingSmall / 2

                        // Store model data as local properties (avoids scope issues in MouseArea handlers)
                        property real presetH: model.h
                        property real presetS: model.s
                        property real presetB: model.b

                        color: ColorUtils.hsbToColor(presetH, presetS, presetB)
                        border.width: 1
                        border.color: Theme.rgba(Theme.primaryColor, 0.2)
                        opacity: presetMouse.pressed ? 0.7 : 1.0

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            // preventStealing stops SilicaFlickable from intercepting
                            // the tap gesture between press and release
                            preventStealing: true
                            onClicked: {
                                console.log("[ColorPicker] Preset clicked: H=" + presetCell.presetH
                                            + " S=" + presetCell.presetS + " B=" + presetCell.presetB);
                                currentHue = presetCell.presetH;
                                currentSaturation = presetCell.presetS;
                                currentBrightness = presetCell.presetB;
                                svCanvas.requestPaint();
                            }
                        }
                    }
                }
            }

            // Bottom spacer
            Item { width: 1; height: Theme.paddingLarge }
        }
    }

    // ── Populate preset color grid on creation ───────────────────────
    Component.onCompleted: {
        var presets = [
            // Row 1 – Grayscale
            { h: 0, s: 0, b: 100 },
            { h: 0, s: 0, b: 83  },
            { h: 0, s: 0, b: 67  },
            { h: 0, s: 0, b: 50  },
            { h: 0, s: 0, b: 33  },
            { h: 0, s: 0, b: 17  },
            { h: 0, s: 0, b: 0   },

            // Row 2 – Saturated bright
            { h: 0,   s: 100, b: 100 },
            { h: 30,  s: 100, b: 100 },
            { h: 60,  s: 100, b: 100 },
            { h: 120, s: 100, b: 100 },
            { h: 180, s: 100, b: 100 },
            { h: 240, s: 100, b: 100 },
            { h: 300, s: 100, b: 100 },

            // Row 3 – Saturated dark
            { h: 0,   s: 100, b: 65 },
            { h: 30,  s: 100, b: 65 },
            { h: 60,  s: 100, b: 65 },
            { h: 120, s: 100, b: 65 },
            { h: 180, s: 100, b: 65 },
            { h: 240, s: 100, b: 65 },
            { h: 300, s: 100, b: 65 },

            // Row 4 – Pastel / soft
            { h: 0,   s: 40, b: 100 },
            { h: 30,  s: 40, b: 100 },
            { h: 60,  s: 40, b: 100 },
            { h: 120, s: 40, b: 100 },
            { h: 180, s: 40, b: 100 },
            { h: 240, s: 40, b: 100 },
            { h: 300, s: 40, b: 100 },

            // Row 5 – Warm / cool whites
            { h: 30,  s: 20, b: 100 },
            { h: 45,  s: 15, b: 100 },
            { h: 60,  s: 10, b: 100 },
            { h: 180, s: 15, b: 100 },
            { h: 210, s: 20, b: 100 },
            { h: 240, s: 15, b: 100 },
            { h: 270, s: 10, b: 100 }
        ];

        for (var i = 0; i < presets.length; i++) {
            presetModel.append(presets[i]);
        }

        hueCanvas.requestPaint();
        svCanvas.requestPaint();

        _ready = true;
    }
}
