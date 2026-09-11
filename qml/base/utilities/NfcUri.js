.pragma library

/**
 * Build and parse the openhab:// URIs stored on NFC tags.
 *
 * The format is dictated by the openHAB Android app -- a tag written there has
 * to work here and the other way round, so nothing in this file may be changed
 * without breaking that compatibility:
 *
 *     item command   openhab://?i=<item>&s=<state>[&l=<label>][&m=<mapped>][&d=true]
 *     sitemap        openhab:///<path behind /rest/sitemaps>
 *
 * Only these five parameters exist. Inventing extra ones would produce tags
 * that Android cannot read.
 */

var SCHEME = "openhab"

// Parameter names. The long ones are deprecated aliases that Android still
// reads but no longer writes -- we do exactly the same (flow decision).
var PARAM_ITEM = "i"
var PARAM_STATE = "s"
var PARAM_LABEL = "l"
var PARAM_MAPPED = "m"
var PARAM_DEVICE_ID = "d"
var DEPRECATED_ITEM = "item"
var DEPRECATED_STATE = "command"


function _encode(value) {
    return encodeURIComponent(value === undefined || value === null ? "" : String(value))
}

/**
 * Full item URI including the display-only fields. Empty optional values are
 * left out entirely rather than written as empty parameters.
 */
function buildItemUri(item, command, label, mappedState) {
    if (!item || !command) return ""
    var uri = SCHEME + "://?" + PARAM_ITEM + "=" + _encode(item)
            + "&" + PARAM_STATE + "=" + _encode(command)
    if (label) uri += "&" + PARAM_LABEL + "=" + _encode(label)
    if (mappedState) uri += "&" + PARAM_MAPPED + "=" + _encode(mappedState)
    return uri
}

/**
 * Minimal item URI. Written when the long form does not fit into the tag;
 * carries everything that is functionally required.
 */
function buildShortItemUri(item, command) {
    return buildItemUri(item, command, "", "")
}

/**
 * Sitemap URI. `path` is what follows /rest/sitemaps, with or without the
 * leading slash -- e.g. "demo" or "/demo/0100".
 */
function buildSitemapUri(path) {
    if (!path) return ""
    var p = String(path)
    if (p.charAt(0) !== "/") p = "/" + p
    // Encode each segment on its own so the separators survive.
    var segments = p.split("/")
    for (var i = 0; i < segments.length; i++) {
        segments[i] = _encode(segments[i])
    }
    return SCHEME + "://" + segments.join("/")
}

/**
 * The sitemap name a path belongs to -- the first segment. Needed because
 * settings.lastVisitedPage only ever holds a bare sitemap name, never a
 * URL: persisting a subpage there would start the app without SSE.
 */
function rootSitemapOf(path) {
    if (!path) return ""
    var segments = String(path).split("/")
    for (var i = 0; i < segments.length; i++) {
        if (segments[i] !== "") return segments[i]
    }
    return ""
}

function _emptyResult(reason) {
    return {
        valid: false,
        kind: "",
        reason: reason,
        item: "",
        command: "",
        label: "",
        mappedState: "",
        path: "",
        rootSitemap: ""
    }
}

function _decode(value) {
    try {
        return decodeURIComponent(value)
    } catch (e) {
        // A malformed escape sequence must not throw out of the read path.
        return value
    }
}

/**
 * Parse a URI read from a tag.
 *
 * Returns an object with `valid`, `kind` ("item" or "sitemap") and the
 * extracted fields. On rejection `reason` says why, so the caller can tell a
 * foreign tag (ignore silently) from a broken openHAB tag (report it).
 */
function parse(uri) {
    if (!uri) return _emptyResult("empty")

    var text = String(uri)
    var colon = text.indexOf(":")
    if (colon < 0) return _emptyResult("notOpenhab")
    if (text.substring(0, colon).toLowerCase() !== SCHEME) {
        return _emptyResult("notOpenhab")
    }

    var rest = text.substring(colon + 1)
    if (rest.indexOf("//") === 0) rest = rest.substring(2)

    // Query form -> item command. Path form -> sitemap.
    var queryStart = rest.indexOf("?")
    if (queryStart === 0) {
        return _parseItem(rest.substring(1))
    }
    if (rest.charAt(0) === "/") {
        // Tolerate a query on the path form; Android never writes one.
        var path = queryStart >= 0 ? rest.substring(0, queryStart) : rest
        return _parseSitemap(path)
    }
    if (queryStart > 0) {
        return _parseItem(rest.substring(queryStart + 1))
    }
    return _emptyResult("notOpenhab")
}

function _parseItem(query) {
    var result = _emptyResult("")
    var deviceIdMode = false

    var pairs = query.split("&")
    for (var i = 0; i < pairs.length; i++) {
        if (pairs[i] === "") continue
        var eq = pairs[i].indexOf("=")
        var key = eq < 0 ? pairs[i] : pairs[i].substring(0, eq)
        var value = eq < 0 ? "" : _decode(pairs[i].substring(eq + 1))

        switch (key) {
        case PARAM_ITEM:
        case DEPRECATED_ITEM:
            if (result.item === "") result.item = value
            break
        case PARAM_STATE:
        case DEPRECATED_STATE:
            if (result.command === "") result.command = value
            break
        case PARAM_LABEL:
            result.label = value
            break
        case PARAM_MAPPED:
            result.mappedState = value
            break
        case PARAM_DEVICE_ID:
            deviceIdMode = (value.toLowerCase() === "true")
            break
        default:
            break   // unknown parameters are ignored, not an error
        }
    }

    if (deviceIdMode) {
        // Android replaces the state with its own device id here, which is why
        // such tags carry s=UNSUPPORTED. Sending that verbatim would be wrong,
        // so the tag is rejected rather than acted upon.
        return _emptyResult("deviceId")
    }
    if (result.item === "") return _emptyResult("missingItem")
    if (result.command === "") return _emptyResult("missingCommand")

    result.valid = true
    result.kind = "item"
    return result
}

function _parseSitemap(path) {
    var segments = path.split("/")
    var decoded = []
    for (var i = 0; i < segments.length; i++) {
        decoded.push(_decode(segments[i]))
    }
    var cleanPath = decoded.join("/")

    var result = _emptyResult("")
    result.path = cleanPath
    result.rootSitemap = rootSitemapOf(cleanPath)
    if (result.rootSitemap === "") return _emptyResult("missingSitemap")

    result.valid = true
    result.kind = "sitemap"
    return result
}

/**
 * True when the path points at a subpage rather than a sitemap root.
 * Used when opening a sitemap tag: navigate to the subpage, but persist
 * only the root.
 */
function isSubPagePath(path) {
    if (!path) return false
    var segments = String(path).split("/")
    var count = 0
    for (var i = 0; i < segments.length; i++) {
        if (segments[i] !== "") count++
    }
    return count > 1
}
