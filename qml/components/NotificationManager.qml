import QtQuick 2.0
import Nemo.Notifications 1.0

/**
 * Central place for user notifications.
 *
 * This has to be a QML component rather than the originally planned
 * NotificationManager.js: a .js library cannot `import Nemo.Notifications`,
 * because JS libraries have no access to QML module imports.
 *
 * Instantiate once in the ApplicationWindow; everything else (pages and the
 * cover) reaches it through that id, the same way `settings` is used.
 *
 * Every call publishes its own Notification object. Reusing one object meant
 * close() + publish(), and close() also removed the previous entry from the
 * events view -- a second NFC tag or a cover error wiped the first message.
 *
 * Built to grow: openHAB cloud notifications are meant to arrive here later,
 * which is why urgency is a parameter rather than hard-coded per call site.
 */
Item {
    id: notificationManager

    /** Fired when the user taps the banner or the entry in the list. */
    signal notificationClicked()

    // Live Notification objects. Kept referenced so they are not garbage
    // collected while the entry is still shown (its clicked signal must keep
    // working); removed again once the system reports the entry closed.
    property var _active: []
    // Upper bound for _active, in case the system never reports "closed".
    readonly property int _maxActive: 20

    Component {
        id: notificationComponent

        Notification {
            id: notificationItem
            appName: "openHAB"
            appIcon: "harbour-openhab"
            category: "x-nemo.generic"

            onClicked: notificationManager.notificationClicked()
            onClosed: notificationManager._release(notificationItem)
        }
    }

    function _urgency(name, isError) {
        switch (name) {
        case "low":      return Notification.Low
        case "normal":   return Notification.Normal
        case "critical": return Notification.Critical
        default:         return isError ? Notification.Critical : Notification.Normal
        }
    }

    function _release(item) {
        var index = _active.indexOf(item)
        if (index >= 0) _active.splice(index, 1)
        item.destroy()
    }

    /**
     * Show a notification.
     *
     * summary/body feed the entry in the notification list, previewSummary and
     * previewBody the banner that pops up over the current view -- without the
     * preview pair there is no banner at all, only a silent list entry.
     *
     * @param summary  short headline, already translated
     * @param body     detail line, already translated
     * @param isError  raises the urgency so the banner is distinguishable
     * @param options  optional:
     *                 transient     -- banner only, no entry in the events view
     *                 expireTimeout -- ms until the notification is removed;
     *                                  default 0 = stays until the user clears it
     *                 urgency       -- "low", "normal" or "critical"; overrides
     *                                  the urgency derived from isError (a string,
     *                                  so callers need no Nemo.Notifications import)
     *                 icon          -- icon shown in the banner/entry
     */
    function notify(summary, body, isError, options) {
        options = options || {}

        var n = notificationComponent.createObject(notificationManager, {
            "summary": summary,
            "body": body || "",
            "previewSummary": summary,
            "previewBody": body || "",
            "urgency": _urgency(options.urgency, isError),
            "expireTimeout": options.expireTimeout !== undefined ? options.expireTimeout : 0,
            "isTransient": options.transient === true
        })
        if (!n) {
            console.warn("[NotificationManager] could not create notification: " + summary)
            return
        }
        if (options.icon) n.icon = options.icon

        _active.push(n)
        while (_active.length > _maxActive) {
            _active.shift().destroy()
        }
        n.publish()
    }

    function notifyError(summary, body, options) {
        notify(summary, body, true, options)
    }

    function notifySuccess(summary, body, options) {
        notify(summary, body, false, options)
    }
}
