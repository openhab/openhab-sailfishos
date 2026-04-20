.pragma library

/**
 * Extracts a usable image source URL from an openHAB Image item state.
 * The state typically arrives as "data:image/webp;base64,UklGR..."
 * QML Image can directly consume data URIs, so we just validate and return it.
 * Returns empty string if the state is not a valid data URI.
 */
function imageSourceFromState(state) {
    if (!state || state === "" || state === "NULL" || state === "UNDEF")
        return "";
    // Already a data URI – use directly
    if (state.indexOf("data:image/") === 0)
        return state;
    // Plain URL (http/https)
    if (state.indexOf("http") === 0)
        return state;
    return "";
}

