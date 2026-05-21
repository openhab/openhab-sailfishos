// ColorUtils.js – HSB↔Color conversion utilities for openHAB Color items
// openHAB HSB format: Hue (0-360), Saturation (0-100), Brightness/Value (0-100)
// NOTE: No .pragma library – requires QML context for Qt.rgba()

/**
 * Convert HSB values to a QML color.
 * @param {number} h - Hue (0-360)
 * @param {number} s - Saturation (0-100)
 * @param {number} v - Brightness/Value (0-100)
 * @returns {color} QML color value
 */
function hsbToColor(h, s, v) {
    var rgb = _hsbToRgbNormalized(h, s, v);
    return Qt.rgba(rgb[0], rgb[1], rgb[2], 1);
}

/**
 * Convert HSB values to CSS rgb() string for Canvas Context2D usage.
 * @param {number} h - Hue (0-360)
 * @param {number} s - Saturation (0-100)
 * @param {number} v - Brightness/Value (0-100)
 * @returns {string} CSS color string, e.g. "rgb(255,128,0)"
 */
function hsbToCss(h, s, v) {
    var rgb = _hsbToRgbNormalized(h, s, v);
    return "rgb(" + Math.round(rgb[0] * 255) + ","
                  + Math.round(rgb[1] * 255) + ","
                  + Math.round(rgb[2] * 255) + ")";
}

/**
 * Parse openHAB HSB state string into object.
 * Handles "H,S,B" format as well as "ON"/"OFF" special states.
 * @param {string} stateStr - e.g. "35,100,49" or "ON"/"OFF"
 * @returns {{ h: number, s: number, b: number }}
 */
function parseHsb(stateStr) {
    if (!stateStr || stateStr === "" || stateStr === "NULL" || stateStr === "UNDEF") {
        return { h: 0, s: 0, b: 0 };
    }
    if (stateStr === "ON")  return { h: 0, s: 0, b: 100 };
    if (stateStr === "OFF") return { h: 0, s: 0, b: 0 };

    var parts = stateStr.split(",");
    if (parts.length >= 3) {
        return {
            h: parseFloat(parts[0]) || 0,
            s: parseFloat(parts[1]) || 0,
            b: parseFloat(parts[2]) || 0
        };
    }
    return { h: 0, s: 0, b: 0 };
}

// ── Internal helper ─────────────────────────────────────────────────

/**
 * HSB → normalized RGB array [r, g, b] with values 0..1
 */
function _hsbToRgbNormalized(h, s, v) {
    var hh = (((h % 360) + 360) % 360) / 360;
    var ss = Math.max(0, Math.min(1, s / 100));
    var vv = Math.max(0, Math.min(1, v / 100));

    var i = Math.floor(hh * 6);
    var f = hh * 6 - i;
    var p = vv * (1 - ss);
    var q = vv * (1 - f * ss);
    var t = vv * (1 - (1 - f) * ss);

    var r, g, b;
    switch (i % 6) {
        case 0: r = vv; g = t;  b = p;  break;
        case 1: r = q;  g = vv; b = p;  break;
        case 2: r = p;  g = vv; b = t;  break;
        case 3: r = p;  g = q;  b = vv; break;
        case 4: r = t;  g = p;  b = vv; break;
        case 5: r = vv; g = p;  b = q;  break;
        default: r = 0; g = 0; b = 0;
    }

    return [r, g, b];
}

