// SitemapLoader.js
/**
 * @param {string} baseUrl - Base-URL of openHAB-Server
 * @param {ListModel} model - ListModel, where sitemaps will be stored
 * @param {function} onSuccess - Callback-Function on successfull call (optional)
 * @param {function} onError - Callback-Function on error (optional)
 */
function loadAvailableSitemaps(baseUrl, model, onSuccess, onError) {
    var url = baseUrl + "/rest/sitemaps/"
    console.log("[SitemapLoader] Loading sitemaps from: " + url)

    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    model.clear()

                    if (Array.isArray(data)) {
                        console.log("[SitemapLoader] Found " + data.length + " sitemaps")
                        data.forEach(function(sitemap) {
                            model.append({
                                name: sitemap.name,
                                label: sitemap.label || sitemap.name
                            })
                        })
                    }

                    if (typeof onSuccess === "function") {
                        onSuccess(data)
                    }
                } catch (e) {
                    console.log("[SitemapLoader] Error parsing sitemaps: " + e)
                    if (typeof onError === "function") {
                        onError(e)
                    }
                }
            } else {
                console.log("[SitemapLoader] HTTP Error: " + xhr.status)
                if (typeof onError === "function") {
                    onError("HTTP Error: " + xhr.status)
                }
            }
        }
    }
    xhr.open("GET", url, true)
    xhr.send()
}

