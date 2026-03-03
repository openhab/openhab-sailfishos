.pragma library
// SseEvents.js

/**
 * Central SSE management (singleton - .pragma library):
 * - startSSE(): Connects SSE and registers the message handler (once)
 * - stopSSE(): Disconnects SSE and deregisters the message handler
 * - restartSSE(): Stops the existing connection and starts a new one
 * - rebindModel(): Rebinds the handler to a different model without reconnecting
 *
 * Because of .pragma library, there is exactly ONE instance of these variables
 * shared across all QML files that import this script.
 */

// The currently active handler function
var _currentHandler = null;
// The model currently receiving updates
var _currentModel = null;
// Reference to the sseManager for disconnect operations
var _sseManager = null;

/**
 * Starts the SSE connection and registers the message handler.
 * If already connected, cleanly disconnects first.
 * @param {object} sseManager - The global SSEManager (C++)
 * @param {string} baseUrl - The openHAB base URL
 * @param {ListModel} model - The sitemapModel for updates
 */
function startSSE(sseManager, baseUrl, model) {
    if (!sseManager) {
        console.error("[SseEvents] SSEManager not available!");
        return;
    }

    // First cleanly disconnect any existing connection
    stopSSE(sseManager);

    _sseManager = sseManager;
    _currentModel = model;

    // Create handler that delegates to handleSSEMessage using the stored _currentModel
    _currentHandler = function(message) {
        handleSSEMessage(message);
    };

    sseManager.messageReceived.connect(_currentHandler);
    sseManager.connectToOpenHAB(baseUrl);
    console.log("[SseEvents] SSE started for: " + baseUrl);
}

/**
 * Stops the SSE connection and deregisters the message handler.
 * @param {object} sseManager - The global SSEManager (C++)
 */
function stopSSE(sseManager) {
    var mgr = sseManager || _sseManager;
    if (!mgr) return;

    if (_currentHandler !== null) {
        try {
            mgr.messageReceived.disconnect(_currentHandler);
        } catch (e) {
            // Can be ignored if handler was already disconnected
        }
        _currentHandler = null;
    }

    mgr.disconnectFromOpenHAB();
    _currentModel = null;
    _sseManager = null;
    console.log("[SseEvents] SSE stopped.");
}

/**
 * Restarts the SSE connection (e.g. on sitemap change or URL change).
 */
function restartSSE(sseManager, baseUrl, model) {
    console.log("[SseEvents] SSE restarting...");
    startSSE(sseManager, baseUrl, model);
}

/**
 * Rebinds the SSE handler to a different model without reconnecting.
 * Use this when navigating to a sub-page (bind to sub-page model)
 * or returning from a sub-page (bind back to parent model).
 * @param {ListModel} model - The new model to receive updates
 */
function rebindModel(model) {
    _currentModel = model;
    console.log("[SseEvents] Model rebound (count: " + (model ? model.count : "null") + ")");
}

// --- Message handling ---

/**
 * Processes an SSE message and updates the currently bound model.
 * Uses the top-level 'itemName' role for reliable matching.
 * Only processes ItemStateChangedEvent to avoid duplicate updates.
 */
function handleSSEMessage(message) {
    if (!message || !_currentModel) return;

    try {
        var event = JSON.parse(message);

        // Only handle ItemStateChangedEvent (skip ItemStateEvent to avoid duplicates)
        if (event.type !== "ItemStateChangedEvent") return;

        var topicParts = event.topic.split('/');
        var itemName = topicParts[2];

        var payload;
        if (typeof event.payload === "string") {
            payload = JSON.parse(event.payload);
        } else {
            payload = event.payload;
        }

        var newState = (payload.value !== undefined) ? payload.value : payload.state;

        if (!itemName || newState === undefined) return;

        var model = _currentModel;
        console.log("[SseEvents] Update received for: " + itemName + " New value: " + newState + " (model count: " + model.count + ")");

        // Iterate model and match by top-level itemName role
        for (var i = 0; i < model.count; i++) {
            var entry = model.get(i);
            var entryItemName = entry.itemName;

            if (entryItemName === itemName) {
                var data = entry.itemData;
                var currentState = data ? data.state : undefined;

                if (currentState !== undefined && currentState === newState.toString()) {
                    console.log("[SseEvents] State unchanged for row " + i + " - skipping");
                    return;
                }

                data.state = newState.toString();
                model.setProperty(i, "itemData", data);
                console.log("[SseEvents] Successfully updated: row " + i + " item: " + itemName + " -> " + newState);
                return;
            }
        }

        // No match found - normal for items not on current sitemap page
    } catch (e) {
        console.log("[SseEvents] Error parsing message: " + e);
    }
}

