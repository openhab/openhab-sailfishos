#ifndef NFCMANAGER_H
#define NFCMANAGER_H

#include <QByteArray>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>

class QDBusPendingCallWatcher;
class QTimer;

/**
 * Talks to nfcd over the D-Bus system bus.
 *
 * Everything in here is asynchronous. That is not decoration: Tag.Acquire2()
 * can block until a tag shows up, and ReadAllData/WriteData take long enough
 * to be felt, so a synchronous call would freeze the UI.
 *
 * The connection is opened once and kept -- nfcd deactivates a tag as soon as
 * the client that found it goes away, which is exactly why the dbus-send based
 * dump script could not read raw memory reliably. For the same reason
 * every tag access is wrapped in Acquire2/Release2.
 *
 * Deliberately kept free of NfcCodec's byte fiddling; the codec is a separate,
 * unit-tested class.
 */
class NfcManager : public QObject
{
    Q_OBJECT

    /** An NFC adapter exists on this device at all. */
    Q_PROPERTY(bool available READ isAvailable NOTIFY availableChanged)
    /** NFC is switched on in the system settings. */
    Q_PROPERTY(bool systemEnabled READ isSystemEnabled NOTIFY systemEnabledChanged)
    /** The read path is armed. */
    Q_PROPERTY(bool listening READ isListening NOTIFY listeningChanged)
    /** A write is in progress and the read path is muted. */
    Q_PROPERTY(bool writing READ isWriting NOTIFY writingChanged)

public:
    explicit NfcManager(QObject *parent = nullptr);
    ~NfcManager();

    bool isAvailable() const { return !m_adapters.isEmpty(); }
    bool isSystemEnabled() const { return m_systemEnabled; }
    bool isListening() const { return m_listening; }
    bool isWriting() const { return m_writing; }

public slots:
    /** Arm the read path. Tags already on the reader are ignored. */
    void startListening();
    void stopListening();

    /**
     * Write a tag. `uri` is the preferred (long) form, `shortUri` the fallback
     * used when the long one does not fit; pass an empty string to skip
     * the fallback. Completion arrives as writeFinished().
     */
    void writeUri(const QString &uri, const QString &shortUri);

    /** Abort a pending write, e.g. when the user closes the dialog. */
    void cancelWrite();

    /**
     * Mute the read path for as long as an NFC page is open.
     *
     * Muting only while WriteData is in flight is not enough: a tag read that
     * arrives while the user is on the way to the write page navigates the app
     * elsewhere, which destroys the write page, which cancels the write, which
     * re-arms the reader -- and the tag is still lying on the phone, so the
     * whole thing repeats. Calls nest, so several pages may hold it at once.
     */
    void suspendReading();
    void resumeReading();

    /** Re-read adapter list and system setting. */
    void refresh();

signals:
    /** A tag carrying an NDEF URI record was read. QML parses it (NfcUri.js). */
    void tagRead(const QString &uri);

    /**
     * A write finished. `errorCode` is empty on success, otherwise one of:
     * "noTag", "unsupportedTagType", "readFailed", "tagTooSmall",
     * "writeFailed", "tagRemoved", "cancelled". `detail` carries the raw
     * D-Bus error for the log, never for the UI.
     */
    void writeFinished(bool success, const QString &errorCode, const QString &detail);

    /** A tag was found and the write is now actually running. */
    void writeStarted();

    void availableChanged();
    void systemEnabledChanged();
    void listeningChanged();
    void writingChanged();

private slots:
    void onTagsChanged(const QDBusMessage &message);
    void onSystemEnabledChanged(const QDBusMessage &message);

    void onAdaptersReply(QDBusPendingCallWatcher *watcher);
    void onSettingsEnabledReply(QDBusPendingCallWatcher *watcher);
    void onInitialTagsReply(QDBusPendingCallWatcher *watcher);

    void onNdefRecordsReply(QDBusPendingCallWatcher *watcher);
    void onNdefGetAllReply(QDBusPendingCallWatcher *watcher);
    void onSerialReply(QDBusPendingCallWatcher *watcher);

    void onWriteTagsReply(QDBusPendingCallWatcher *watcher);
    void onAcquireReply(QDBusPendingCallWatcher *watcher);
    void onReadAllDataReply(QDBusPendingCallWatcher *watcher);
    void onWriteDataReply(QDBusPendingCallWatcher *watcher);

    void onWriteTimeout();

private:
    void callAsync(const QString &service,
                   const QString &path,
                   const QString &interface,
                   const QString &method,
                   const QVariantList &args,
                   const char *slot,
                   int timeoutMs,
                   const QString &tagPath);

    void subscribeIfNeeded();
    void unsubscribeIfIdle();
    /** Mark everything currently on the reader as "do not act on this". */
    void ignoreCurrentTags();
    void handleNewTag(const QString &tagPath);
    void forgetTag(const QString &tagPath);
    void beginWrite(const QString &tagPath);
    void finishWrite(bool success, const QString &code, const QString &detail);
    void releaseTag(const QString &tagPath);
    bool debounce(const QByteArray &serial, const QString &uri);
    void setWriting(bool writing);

    static QStringList objectPathsFrom(const QVariant &variant);

    QDBusConnection m_bus;
    QStringList m_adapters;
    bool m_systemEnabled = false;
    bool m_listening = false;
    bool m_writing = false;
    bool m_subscribed = false;
    /** True until GetTags() told us what was already lying on the reader. */
    bool m_awaitingInitialTags = false;
    /** Whether Acquire2 succeeded, so we know if a Release2 is owed. */
    bool m_tagAcquired = false;
    /** Nesting depth of suspendReading(); reading is muted while > 0. */
    int m_readSuppression = 0;

    /**
     * Tags that were already on the reader when listening started. They must
     * not fire a command. nfcd hands out a fresh object path for every
     * detection, so an entry becomes irrelevant by itself once the tag
     * is lifted.
     */
    QSet<QString> m_ignoredTagPaths;

    /** Tag paths currently being examined, so a repeat signal does no harm. */
    QSet<QString> m_inFlightTagPaths;

    /** Read state per tag path, collected across the async round trips. */
    struct PendingRead {
        QString uri;
    };
    QHash<QString, PendingRead> m_pendingReads;

    /**
     * Debounce cache: NFCID1 + URI -> when it last fired. Keyed on the tag
     * serial rather than the object path, because the path changes on every
     * detection.
     */
    QHash<QString, qint64> m_recentTags;
    QElapsedTimer m_clock;

    // ── write job ──
    QString m_writeUri;
    QString m_writeShortUri;
    QString m_writeTagPath;
    QByteArray m_writeImage;
    bool m_writePending = false;
    QTimer *m_writeTimeout = nullptr;
};

#endif // NFCMANAGER_H
