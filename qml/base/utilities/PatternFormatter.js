.pragma library

/**
 * PatternFormatter.js
 *
 * Formats raw openHAB item states using Java String.format patterns
 * commonly used in openHAB sitemap definitions.
 *
 * Supported patterns:
 *   DateTime:  %1$td (day), %1$tm (month), %1$tY (year 4-digit), %1$ty (year 2-digit),
 *              %1$tH (hour 24h), %1$tM (minute), %1$tS (second),
 *              %1$ta (short weekday), %1$tA (long weekday),
 *              %1$tb / %1$th (short month name), %1$tB (long month name),
 *              %1$tF (ISO date: YYYY-MM-DD), %1$tD (US date: MM/DD/YY),
 *              %1$tT (time: HH:MM:SS), %1$tR (time: HH:MM)
 *   Number:    %d (integer), %.Nf (float with N decimals), %s (string)
 *   Literal:   %% → %
 */

/**
 * Format a raw state value using an openHAB pattern string.
 *
 * @param {string} pattern  - The Java String.format pattern (e.g. "%1$td.%1$tm.%1$tY %1$tH:%1$tM Uhr")
 * @param {string} rawState - The raw state value from SSE or REST API
 * @returns {string} The formatted string, or rawState if formatting fails
 */
function formatState(pattern, rawState) {
    if (!pattern || !rawState || rawState === "NULL" || rawState === "UNDEF") {
        return rawState || "";
    }

    try {
        // Check if pattern contains date/time placeholders
        if (pattern.indexOf("%1$t") !== -1) {
            return formatDateTime(pattern, rawState);
        }

        // Number / string formatting
        return formatNumber(pattern, rawState);
    } catch (e) {
        console.log("[PatternFormatter] Error formatting '" + rawState + "' with pattern '" + pattern + "': " + e);
        return rawState;
    }
}

/**
 * Zero-pad a number to a given width.
 */
function zeroPad(num, width) {
    var s = num.toString();
    while (s.length < width) s = "0" + s;
    return s;
}

/**
 * Format a DateTime state using a Java date/time pattern.
 * Expects rawState as ISO-8601 string (e.g. "2026-03-10T13:17:38.000+0100")
 */
function formatDateTime(pattern, rawState) {
    // Parse ISO-8601 date string
    var d = new Date(rawState);
    if (isNaN(d.getTime())) {
        // Try to handle openHAB's timezone format (+0100 instead of +01:00)
        var fixed = rawState.replace(/([+-]\d{2})(\d{2})$/, "$1:$2");
        d = new Date(fixed);
        if (isNaN(d.getTime())) {
            return rawState;
        }
    }

    var result = pattern;

    // Replace %% with a temporary placeholder to avoid conflicts
    result = result.replace(/%%/g, "\x00PERCENT\x00");

    // Composite date/time shortcuts (must be replaced BEFORE individual tokens)
    // %1$tF → ISO date: YYYY-MM-DD  (e.g. "2026-03-12")
    result = result.replace(/%1\$tF/g, d.getFullYear().toString() + "-" + zeroPad(d.getMonth() + 1, 2) + "-" + zeroPad(d.getDate(), 2));
    // %1$tD → US date: MM/DD/YY  (e.g. "03/12/26")
    result = result.replace(/%1\$tD/g, zeroPad(d.getMonth() + 1, 2) + "/" + zeroPad(d.getDate(), 2) + "/" + zeroPad(d.getFullYear() % 100, 2));
    // %1$tT → time: HH:MM:SS
    result = result.replace(/%1\$tT/g, zeroPad(d.getHours(), 2) + ":" + zeroPad(d.getMinutes(), 2) + ":" + zeroPad(d.getSeconds(), 2));
    // %1$tR → time: HH:MM
    result = result.replace(/%1\$tR/g, zeroPad(d.getHours(), 2) + ":" + zeroPad(d.getMinutes(), 2));

    // Date/time replacements (order matters: longer patterns first)
    result = result.replace(/%1\$tY/g, d.getFullYear().toString());
    result = result.replace(/%1\$ty/g, zeroPad(d.getFullYear() % 100, 2));
    result = result.replace(/%1\$tm/g, zeroPad(d.getMonth() + 1, 2));
    result = result.replace(/%1\$td/g, zeroPad(d.getDate(), 2));
    result = result.replace(/%1\$te/g, d.getDate().toString());
    result = result.replace(/%1\$tH/g, zeroPad(d.getHours(), 2));
    result = result.replace(/%1\$tk/g, d.getHours().toString());
    result = result.replace(/%1\$tI/g, zeroPad(d.getHours() % 12 || 12, 2));
    result = result.replace(/%1\$tl/g, (d.getHours() % 12 || 12).toString());
    result = result.replace(/%1\$tM/g, zeroPad(d.getMinutes(), 2));
    result = result.replace(/%1\$tS/g, zeroPad(d.getSeconds(), 2));

    // Short weekday names (German locale – can be extended)
    var weekdaysShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
    var weekdaysLong = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
    result = result.replace(/%1\$tA/g, weekdaysLong[d.getDay()]);
    result = result.replace(/%1\$ta/g, weekdaysShort[d.getDay()]);

    var monthsShort = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];
    var monthsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
    result = result.replace(/%1\$tB/g, monthsLong[d.getMonth()]);
    result = result.replace(/%1\$tb/g, monthsShort[d.getMonth()]);
    result = result.replace(/%1\$th/g, monthsShort[d.getMonth()]);

    // AM/PM
    result = result.replace(/%1\$tp/g, d.getHours() < 12 ? "am" : "pm");

    // Restore literal %
    result = result.replace(/\x00PERCENT\x00/g, "%");

    return result;
}

/**
 * Format a Number or String state using a Java number pattern.
 * Handles: %d, %.Nf, %s, %unit% and patterns with surrounding text (e.g. "%.1f %unit%", "%d %%")
 *
 * rawState may be a pure number ("23.5") or include a unit ("23.5 W", "374.0 kWh").
 */
function formatNumber(pattern, rawState) {
    // Split rawState into numeric part and unit part
    // Examples: "11.1 W" → num="11.1", unit="W"
    //           "374.0 kWh" → num="374.0", unit="kWh"
    //           "23" → num="23", unit=""
    var parts = rawState.match(/^(-?[\d.]+)\s*(.*)$/);
    var numVal = NaN;
    var unit = "";
    if (parts) {
        numVal = parseFloat(parts[1]);
        unit = parts[2] || "";
    }

    var result = pattern;

    // Replace %% with temporary placeholder
    result = result.replace(/%%/g, "\x00PERCENT\x00");

    // Replace %unit% with the actual unit extracted from rawState
    result = result.replace(/%unit%/g, unit);

    // %.Nf - float with N decimal places
    var floatMatch = result.match(/%(\d*)\.(\d+)f/);
    if (floatMatch) {
        var decimals = parseInt(floatMatch[2], 10);
        if (!isNaN(numVal)) {
            result = result.replace(/%\d*\.\d+f/, numVal.toFixed(decimals));
        } else {
            result = result.replace(/%\d*\.\d+f/, rawState);
        }
    }

    // %d - integer
    if (result.indexOf("%d") !== -1) {
        if (!isNaN(numVal)) {
            result = result.replace(/%d/, Math.round(numVal).toString());
        } else {
            result = result.replace(/%d/, rawState);
        }
    }

    // %s - string (use rawState as-is)
    if (result.indexOf("%s") !== -1) {
        result = result.replace(/%s/, rawState);
    }

    // Restore literal %
    result = result.replace(/\x00PERCENT\x00/g, "%");

    return result;
}

