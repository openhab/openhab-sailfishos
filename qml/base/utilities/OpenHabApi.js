.pragma library

/**
 * Shared openHAB REST access.
 *
 * sendCommand() and getAuthHeader() used to exist twice, copied into
 * SitemapPage.qml and CoverPage.qml, and neither copy had an error path --
 * onreadystatechange only ever looked at the success case. That is tolerable
 * for a sitemap tap, where the user watches the widget, but not for NFC, where
 * the tag is the only interaction and a notification is the only feedback.
 *
 * A `config` object carries what a .js library cannot reach on its own:
 *
 *     { baseUrl: "...", username: "...", password: "..." }
 *
 * The password must already be decoded (settings.decodePassword).
 */

/** Basic auth header, or null when either credential is missing. */
function authHeader(config) {
    if (!config) return null
    var u = config.username
    var p = config.password
    if (u && u !== "" && p && p !== "") {
        return "Basic " + Qt.btoa(u + ":" + p)
    }
    return null
}

/**
 * Classify a finished XMLHttpRequest.
 *
 * Telling 404 apart from "server unreachable" matters: reporting "this item
 * does not exist" when the server is simply off would send the user hunting
 * for the wrong problem.
 */
function classifyError(xhr) {
    var status = xhr.status
    if (status === 0) {
        return { kind: "network", status: 0,
                 message: "Server not reachable" }
    }
    if (status === 401 || status === 403) {
        return { kind: "unauthorized", status: status,
                 message: "Not authorized" }
    }
    if (status === 404) {
        return { kind: "notFound", status: status,
                 message: "Not found on this server" }
    }
    if (status >= 500) {
        return { kind: "server", status: status,
                 message: "Server error " + status }
    }
    return { kind: "http", status: status,
             message: "HTTP " + status }
}

function _open(config, method, path, accept) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, config.baseUrl + path, true)
    if (accept) xhr.setRequestHeader("Accept", accept)
    var auth = authHeader(config)
    if (auth) xhr.setRequestHeader("Authorization", auth)
    return xhr
}

/**
 * POST a command to an item.
 *
 * `onSuccess()` fires when openHAB accepted the command -- which is not the
 * same as the device having reacted, so callers must phrase their feedback
 * accordingly. `onError(errorObject)` fires otherwise; both are
 * optional, so existing fire-and-forget callers keep working unchanged.
 */
function sendCommand(config, itemName, command, onSuccess, onError) {
    if (!itemName || itemName === "") return
    var xhr = _open(config, "POST", "/rest/items/" + encodeURIComponent(itemName))
    xhr.setRequestHeader("Content-Type", "text/plain")
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status >= 200 && xhr.status < 300) {
            if (onSuccess) onSuccess()
        } else {
            console.warn("[OpenHabApi] sendCommand " + itemName + " failed: " + xhr.status)
            if (onError) onError(classifyError(xhr))
        }
    }
    xhr.send(command)
}

/**
 * GET a single item. Used by the NFC read path to check that the item on the
 * tag actually exists on this server before sending anything.
 */
function fetchItem(config, itemName, onSuccess, onError) {
    if (!itemName || itemName === "") {
        if (onError) onError({ kind: "notFound", status: 404, message: "No item name" })
        return
    }
    var xhr = _open(config, "GET", "/rest/items/" + encodeURIComponent(itemName),
                    "application/json")
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                if (onSuccess) onSuccess(JSON.parse(xhr.responseText))
            } catch (e) {
                console.warn("[OpenHabApi] cannot parse item " + itemName + ": " + e)
                if (onError) onError({ kind: "http", status: xhr.status,
                                       message: "Malformed response" })
            }
        } else {
            if (onError) onError(classifyError(xhr))
        }
    }
    xhr.send()
}

/** GET all items. Used by the "show all items" branch of the NFC page. */
function fetchItems(config, onSuccess, onError) {
    var xhr = _open(config, "GET", "/rest/items", "application/json")
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                if (onSuccess) onSuccess(JSON.parse(xhr.responseText))
            } catch (e) {
                console.warn("[OpenHabApi] cannot parse item list: " + e)
                if (onError) onError({ kind: "http", status: xhr.status,
                                       message: "Malformed response" })
            }
        } else {
            if (onError) onError(classifyError(xhr))
        }
    }
    xhr.send()
}

/**
 * Check that a sitemap path exists. `path` is what follows /rest/sitemaps,
 * e.g. "/demo" or "/demo/0100".
 */
function checkSitemapPath(config, path, onSuccess, onError) {
    var xhr = _open(config, "GET", "/rest/sitemaps" + path, "application/json")
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status >= 200 && xhr.status < 300) {
            if (onSuccess) onSuccess()
        } else {
            if (onError) onError(classifyError(xhr))
        }
    }
    xhr.send()
}

/**
 * Commands a given item accepts, in this order:
 *   1. commandDescription.commandOptions from the REST response
 *   2. the widget's mappings[], when the call comes from a sitemap widget
 *   3. the static per-type table (passed in from item-commands.json)
 *
 * Returns a list of { command, label } objects. An empty list means the
 * caller should offer free text input.
 */
function commandsForItem(item, mappings, staticTable) {
    var result = []
    var i

    if (item && item.commandDescription && item.commandDescription.commandOptions) {
        var options = item.commandDescription.commandOptions
        for (i = 0; i < options.length; i++) {
            result.push({ command: options[i].command,
                          label: options[i].label || options[i].command })
        }
        if (result.length > 0) return result
    }

    if (mappings && mappings.length > 0) {
        for (i = 0; i < mappings.length; i++) {
            result.push({ command: mappings[i].command,
                          label: mappings[i].label || mappings[i].command })
        }
        if (result.length > 0) return result
    }

    if (item && staticTable) {
        var type = baseTypeOf(item.type)
        var entry = staticTable[type]
        if (entry) {
            for (i = 0; i < entry.length; i++) {
                result.push({ command: entry[i], label: entry[i] })
            }
        }
    }
    return result
}

/**
 * Collect the commandable items of a sitemap response, depth first, without
 * duplicates.
 *
 * This is the default source for the NFC page's item list:
 * it is short, contextual and needs no extra request, whereas GET /rest/items
 * easily returns several hundred entries on a real installation.
 *
 * `readOnlyTypes` comes from item-commands.json; items of those types are
 * dropped because they cannot take a command at all.
 */
function collectSitemapItems(sitemapJson, readOnlyTypes) {
    var items = []
    var seen = {}
    var skip = readOnlyTypes || []

    function isReadOnly(type) {
        var base = baseTypeOf(type)
        for (var i = 0; i < skip.length; i++) {
            if (skip[i] === base) return true
        }
        return false
    }

    function walk(widgets) {
        if (!widgets) return
        for (var i = 0; i < widgets.length; i++) {
            var w = widgets[i]
            if (w.item && w.item.name && !seen[w.item.name] && !isReadOnly(w.item.type)) {
                seen[w.item.name] = true
                items.push({
                    name: w.item.name,
                    label: (w.label ? String(w.label).split("[")[0].trim() : "")
                           || w.item.label || w.item.name,
                    type: w.item.type || "",
                    // Sitemap mappings win over the static table.
                    mappings: w.mappings || [],
                    commandDescription: w.item.commandDescription || null
                })
            }
            if (w.widgets) walk(w.widgets)
            if (w.linkedPage && w.linkedPage.widgets) walk(w.linkedPage.widgets)
        }
    }

    if (sitemapJson) {
        if (sitemapJson.homepage && sitemapJson.homepage.widgets) {
            walk(sitemapJson.homepage.widgets)
        } else if (sitemapJson.widgets) {
            walk(sitemapJson.widgets)
        }
    }
    return items
}

/** Filter a GET /rest/items response down to items that can take a command. */
function filterCommandableItems(itemsJson, readOnlyTypes) {
    var result = []
    var skip = readOnlyTypes || []
    if (!itemsJson) return result

    for (var i = 0; i < itemsJson.length; i++) {
        var item = itemsJson[i]
        if (!item || !item.name) continue
        var base = baseTypeOf(item.type)
        var readOnly = false
        for (var j = 0; j < skip.length; j++) {
            if (skip[j] === base) { readOnly = true; break }
        }
        if (readOnly) continue
        result.push({
            name: item.name,
            label: item.label || item.name,
            type: item.type || "",
            mappings: [],
            commandDescription: item.commandDescription || null
        })
    }
    return result
}

/**
 * openHAB reports parametrised types as "Number:Temperature" and groups as
 * "Group:Switch". Reduce both to the base type the command table is keyed on.
 */
function baseTypeOf(type) {
    if (!type) return ""
    var t = String(type)
    if (t.indexOf("Group:") === 0) t = t.substring(6)
    var colon = t.indexOf(":")
    if (colon > 0) t = t.substring(0, colon)
    return t
}
