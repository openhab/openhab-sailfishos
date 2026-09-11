import QtQuick 2.0
import Nemo.Notifications 1.0

/**
 * Central place for user notifications.
 *
 * This has to be a QML component rather than the originally planned
 * NotificationManager.js: a .js library cannot `import Nemo.Notifications`,
 * because JS libraries have no access to QML module imports.
 *
 * Instantiate once in the ApplicationWindow; everything else reaches it
 * through that id, the same way `settings` is used.
 *
 * Built to grow: openHAB cloud notifications are meant to arrive here later,
 * which is why urgency is a parameter rather than hard-coded per call site.
 */
Item {
    id: notificationManager

    /** Fired when the user taps the banner or the entry in the list. */
    signal notificationClicked()

    Notification {
        id: notification

        appName: "openHAB"
        appIcon: "harbour-openhab"
        category: "x-nemo.generic"

        // 0 means "never expire": the banner still fades on its own, but the
        // entry stays in the events view until the user clears it. With a
        // timeout the whole notification is removed after that many
        // milliseconds, which took the entry out of the events view too.
        // Set this to e.g. 5000 if a self-clearing notification is preferred.
        expireTimeout: 0

        onClicked: notificationManager.notificationClicked()
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
     */
    function notify(summary, body, isError) {
        // Close first: republishing the same Notification object would replace
        // the previous banner instead of showing a second one, which would
        // swallow the feedback for a rapid second tag.
        notification.close()

        notification.urgency = isError ? Notification.Critical : Notification.Normal
        notification.summary = summary
        notification.body = body || ""
        notification.previewSummary = summary
        notification.previewBody = body || ""
        notification.publish()
    }

    function notifyError(summary, body) {
        notify(summary, body, true)
    }

    function notifySuccess(summary, body) {
        notify(summary, body, false)
    }
}
