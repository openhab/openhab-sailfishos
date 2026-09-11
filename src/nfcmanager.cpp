#include "nfcmanager.h"
#include "nfccodec.h"

#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QTimer>

namespace {

const QString kDaemonService   = QStringLiteral("org.sailfishos.nfc.daemon");
const QString kSettingsService = QStringLiteral("org.sailfishos.nfc.settings");

const QString kIfaceDaemon   = QStringLiteral("org.sailfishos.nfc.Daemon");
const QString kIfaceAdapter  = QStringLiteral("org.sailfishos.nfc.Adapter");
const QString kIfaceTag      = QStringLiteral("org.sailfishos.nfc.Tag");
const QString kIfaceNdef     = QStringLiteral("org.sailfishos.nfc.NDEF");
const QString kIfaceType2    = QStringLiteral("org.sailfishos.nfc.TagType2");
const QString kIfaceSettings = QStringLiteral("org.sailfishos.nfc.Settings");

const QString kRootPath = QStringLiteral("/");

/** How long the same tag+URI combination stays muted. */
const qint64 kDebounceMs = 5000;

/** How long a write waits for a tag before giving up. */
const int kWriteTimeoutMs = 30000;

/** NDEF TNF value for well-known types. */
const uint kTnfWellKnown = 1;

QByteArray byteArrayFrom(const QVariant &variant)
{
    if (variant.type() == QVariant::ByteArray) {
        return variant.toByteArray();
    }
    // Defensive: some nfcd/QtDBus combinations hand an empty 'ay' over as a
    // QDBusArgument rather than a QByteArray.
    if (variant.canConvert<QDBusArgument>()) {
        QByteArray result;
        const QDBusArgument arg = variant.value<QDBusArgument>();
        if (arg.currentType() == QDBusArgument::ArrayType) {
            arg.beginArray();
            while (!arg.atEnd()) {
                uchar byte = 0;
                arg >> byte;
                result.append(char(byte));
            }
            arg.endArray();
        }
        return result;
    }
    return QByteArray();
}

} // namespace

// ---------------------------------------------------------------------------

NfcManager::NfcManager(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::systemBus())
{
    m_clock.start();

    m_writeTimeout = new QTimer(this);
    m_writeTimeout->setSingleShot(true);
    m_writeTimeout->setInterval(kWriteTimeoutMs);
    connect(m_writeTimeout, SIGNAL(timeout()), this, SLOT(onWriteTimeout()));

    if (!m_bus.isConnected()) {
        qWarning() << "[Nfc] no system bus -- NFC feature stays unavailable";
        return;
    }

    // The system setting can change while we run; keep track of it so the UI
    // can point the user at the settings app instead of failing silently.
    m_bus.connect(kSettingsService, kRootPath, kIfaceSettings,
                  QStringLiteral("EnabledChanged"),
                  this, SLOT(onSystemEnabledChanged(QDBusMessage)));

    refresh();
}

NfcManager::~NfcManager()
{
    if (!m_writeTagPath.isEmpty()) {
        releaseTag(m_writeTagPath);
    }
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

void NfcManager::callAsync(const QString &service,
                           const QString &path,
                           const QString &interface,
                           const QString &method,
                           const QVariantList &args,
                           const char *slot,
                           int timeoutMs,
                           const QString &tagPath)
{
    QDBusMessage message =
            QDBusMessage::createMethodCall(service, path, interface, method);
    if (!args.isEmpty()) {
        message.setArguments(args);
    }

    QDBusPendingCall call = m_bus.asyncCall(message, timeoutMs);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    // The reply carries no hint which tag it belongs to, so remember it here.
    watcher->setProperty("tagPath", tagPath);
    connect(watcher, SIGNAL(finished(QDBusPendingCallWatcher*)), this, slot);
}

QStringList NfcManager::objectPathsFrom(const QVariant &variant)
{
    QStringList paths;
    if (!variant.canConvert<QDBusArgument>()) {
        return paths;
    }
    const QDBusArgument arg = variant.value<QDBusArgument>();
    if (arg.currentType() != QDBusArgument::ArrayType) {
        return paths;
    }
    arg.beginArray();
    while (!arg.atEnd()) {
        QDBusObjectPath path;
        arg >> path;
        if (!path.path().isEmpty()) {
            paths << path.path();
        }
    }
    arg.endArray();
    return paths;
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

void NfcManager::refresh()
{
    if (!m_bus.isConnected()) {
        return;
    }
    // Single methods on purpose: the Daemon interface is at version 4 on
    // Sailfish 5.0.0.72, so GetAll6 does not exist there.
    callAsync(kDaemonService, kRootPath, kIfaceDaemon,
              QStringLiteral("GetAdapters"), QVariantList(),
              SLOT(onAdaptersReply(QDBusPendingCallWatcher*)), 5000, QString());

    callAsync(kSettingsService, kRootPath, kIfaceSettings,
              QStringLiteral("GetEnabled"), QVariantList(),
              SLOT(onSettingsEnabledReply(QDBusPendingCallWatcher*)), 5000, QString());
}

void NfcManager::onAdaptersReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[Nfc] GetAdapters failed:" << reply.errorMessage();
        return;
    }

    const QStringList adapters = reply.arguments().isEmpty()
            ? QStringList()
            : objectPathsFrom(reply.arguments().first());

    if (adapters == m_adapters) {
        return;
    }
    const bool wasAvailable = isAvailable();
    const bool wasSubscribed = m_subscribed;

    // Drop the old subscriptions before the adapter list is replaced,
    // otherwise a re-listed adapter would deliver TagsChanged twice.
    if (wasSubscribed) {
        foreach (const QString &adapter, m_adapters) {
            m_bus.disconnect(kDaemonService, adapter, kIfaceAdapter,
                             QStringLiteral("TagsChanged"),
                             this, SLOT(onTagsChanged(QDBusMessage)));
        }
        m_subscribed = false;
    }

    m_adapters = adapters;
    qDebug() << "[Nfc] adapters:" << m_adapters;

    if (wasSubscribed) {
        subscribeIfNeeded();
    }
    if (wasAvailable != isAvailable()) {
        emit availableChanged();
    }
}

void NfcManager::onSettingsEnabledReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[Nfc] Settings.GetEnabled failed:" << reply.errorMessage();
        return;
    }
    const bool enabled = reply.arguments().value(0).toBool();
    if (enabled != m_systemEnabled) {
        m_systemEnabled = enabled;
        emit systemEnabledChanged();
    }
}

void NfcManager::onSystemEnabledChanged(const QDBusMessage &message)
{
    const bool enabled = message.arguments().value(0).toBool();
    if (enabled != m_systemEnabled) {
        m_systemEnabled = enabled;
        emit systemEnabledChanged();
    }
}

// ---------------------------------------------------------------------------
// Subscription
// ---------------------------------------------------------------------------

void NfcManager::subscribeIfNeeded()
{
    if (m_subscribed || m_adapters.isEmpty()) {
        return;
    }
    foreach (const QString &adapter, m_adapters) {
        m_bus.connect(kDaemonService, adapter, kIfaceAdapter,
                      QStringLiteral("TagsChanged"),
                      this, SLOT(onTagsChanged(QDBusMessage)));
    }
    m_subscribed = true;
}

void NfcManager::unsubscribeIfIdle()
{
    if (!m_subscribed || m_listening || m_writePending) {
        return;
    }
    foreach (const QString &adapter, m_adapters) {
        m_bus.disconnect(kDaemonService, adapter, kIfaceAdapter,
                         QStringLiteral("TagsChanged"),
                         this, SLOT(onTagsChanged(QDBusMessage)));
    }
    m_subscribed = false;
}

// ---------------------------------------------------------------------------
// Listening
// ---------------------------------------------------------------------------

void NfcManager::startListening()
{
    if (m_listening || !m_bus.isConnected()) {
        return;
    }
    m_listening = true;
    m_recentTags.clear();
    subscribeIfNeeded();
    ignoreCurrentTags();
    emit listeningChanged();
}

void NfcManager::stopListening()
{
    if (!m_listening) {
        return;
    }
    m_listening = false;
    m_ignoredTagPaths.clear();
    m_inFlightTagPaths.clear();
    m_pendingReads.clear();
    m_recentTags.clear();
    unsubscribeIfIdle();
    emit listeningChanged();
}

void NfcManager::ignoreCurrentTags()
{
    m_ignoredTagPaths.clear();
    m_awaitingInitialTags = true;

    foreach (const QString &adapter, m_adapters) {
        callAsync(kDaemonService, adapter, kIfaceAdapter,
                  QStringLiteral("GetTags"), QVariantList(),
                  SLOT(onInitialTagsReply(QDBusPendingCallWatcher*)), 5000, QString());
    }
    if (m_adapters.isEmpty()) {
        m_awaitingInitialTags = false;
    }
}

void NfcManager::onInitialTagsReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    m_awaitingInitialTags = false;

    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        return;
    }
    const QStringList tags = reply.arguments().isEmpty()
            ? QStringList()
            : objectPathsFrom(reply.arguments().first());
    foreach (const QString &tag, tags) {
        m_ignoredTagPaths.insert(tag);
    }
    if (!tags.isEmpty()) {
        qDebug() << "[Nfc] ignoring tags already present:" << tags;
    }
}

void NfcManager::onTagsChanged(const QDBusMessage &message)
{
    const QStringList tags = message.arguments().isEmpty()
            ? QStringList()
            : objectPathsFrom(message.arguments().first());

    // Drop bookkeeping for tags that went away. nfcd never reuses an object
    // path for a new contact, so this only prunes.
    QSet<QString> present = QSet<QString>::fromList(tags);
    foreach (const QString &known, m_ignoredTagPaths) {
        if (!present.contains(known)) {
            m_ignoredTagPaths.remove(known);
        }
    }

    foreach (const QString &tag, tags) {
        if (m_inFlightTagPaths.contains(tag) || m_ignoredTagPaths.contains(tag)) {
            continue;
        }
        if (m_writePending) {
            if (m_writeTagPath.isEmpty()) {
                beginWrite(tag);
            }
            continue;
        }
        // Reading is muted while a write runs, while an NFC page is open, and
        // until we know which tags were already lying there when listening
        // started.
        if (m_listening && !m_writing && m_readSuppression == 0
                && !m_awaitingInitialTags) {
            handleNewTag(tag);
        }
    }
}

// ---------------------------------------------------------------------------
// Read path
// ---------------------------------------------------------------------------

void NfcManager::handleNewTag(const QString &tagPath)
{
    m_inFlightTagPaths.insert(tagPath);
    m_pendingReads.insert(tagPath, PendingRead());

    callAsync(kDaemonService, tagPath, kIfaceTag,
              QStringLiteral("GetNdefRecords"), QVariantList(),
              SLOT(onNdefRecordsReply(QDBusPendingCallWatcher*)), 5000, tagPath);
}

void NfcManager::onNdefRecordsReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();

    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        forgetTag(tagPath);
        return;
    }
    const QStringList records = reply.arguments().isEmpty()
            ? QStringList()
            : objectPathsFrom(reply.arguments().first());
    if (records.isEmpty()) {
        forgetTag(tagPath);
        return;
    }

    // First matching record wins (flow decision). NDEF.GetAll is at interface
    // version 1 -- the only version there has ever been -- and saves three
    // round trips over the individual getters.
    callAsync(kDaemonService, records.first(), kIfaceNdef,
              QStringLiteral("GetAll"), QVariantList(),
              SLOT(onNdefGetAllReply(QDBusPendingCallWatcher*)), 5000, tagPath);
}

void NfcManager::onNdefGetAllReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();

    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        forgetTag(tagPath);
        return;
    }

    // (i version, u flags, u tnf, as interfaces, ay type, ay id, ay payload)
    const QVariantList args = reply.arguments();
    if (args.size() < 7) {
        forgetTag(tagPath);
        return;
    }
    const uint tnf = args.at(2).toUInt();
    const QByteArray type = byteArrayFrom(args.at(4));
    const QByteArray payload = byteArrayFrom(args.at(6));

    // A factory fresh tag exposes a record too -- an empty one. Every
    // stage here has to pass before the tag counts as ours.
    if (tnf != kTnfWellKnown || type != QByteArray("U") || payload.isEmpty()) {
        forgetTag(tagPath);
        return;
    }

    const QString uri = NfcCodec::uriFromPayload(payload);
    if (uri.isEmpty()) {
        forgetTag(tagPath);
        return;
    }

    PendingRead pending;
    pending.uri = uri;
    m_pendingReads.insert(tagPath, pending);

    // The serial is the debounce key; the object path cannot be used for that
    // because it changes on every detection.
    callAsync(kDaemonService, tagPath, kIfaceType2,
              QStringLiteral("GetSerial"), QVariantList(),
              SLOT(onSerialReply(QDBusPendingCallWatcher*)), 5000, tagPath);
}

void NfcManager::onSerialReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();

    const QString uri = m_pendingReads.value(tagPath).uri;
    if (uri.isEmpty()) {
        forgetTag(tagPath);
        return;
    }

    QByteArray serial;
    const QDBusMessage reply = watcher->reply();
    if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty()) {
        serial = byteArrayFrom(reply.arguments().first());
    }

    forgetTag(tagPath);

    // A read takes three round trips, so muting can begin while one is still
    // in flight. This is the only place that emits, so it is also the right
    // place to drop a read that has become unwanted in the meantime.
    if (m_writing || m_readSuppression > 0 || !m_listening) {
        qDebug() << "[Nfc] discarding read, reading is muted:" << uri;
        return;
    }

    if (!debounce(serial, uri)) {
        qDebug() << "[Nfc] debounced" << uri;
        return;
    }
    qDebug() << "[Nfc] tag read:" << uri;
    emit tagRead(uri);
}

bool NfcManager::debounce(const QByteArray &serial, const QString &uri)
{
    // Without a serial we fall back to the URI alone -- debouncing once too
    // often is better than sending a command twice.
    const QString key = QString::fromLatin1(serial.toHex()) + QLatin1Char('|') + uri;
    const qint64 now = m_clock.elapsed();

    QHash<QString, qint64>::iterator it = m_recentTags.begin();
    while (it != m_recentTags.end()) {
        if (now - it.value() > kDebounceMs) {
            it = m_recentTags.erase(it);
        } else {
            ++it;
        }
    }

    if (m_recentTags.contains(key)) {
        return false;
    }
    m_recentTags.insert(key, now);
    return true;
}

void NfcManager::forgetTag(const QString &tagPath)
{
    m_inFlightTagPaths.remove(tagPath);
    m_pendingReads.remove(tagPath);
}

// ---------------------------------------------------------------------------
// Write path
// ---------------------------------------------------------------------------

void NfcManager::writeUri(const QString &uri, const QString &shortUri)
{
    if (uri.isEmpty()) {
        emit writeFinished(false, QStringLiteral("writeFailed"),
                           QStringLiteral("empty URI"));
        return;
    }
    if (!m_bus.isConnected() || m_adapters.isEmpty()) {
        emit writeFinished(false, QStringLiteral("noTag"),
                           QStringLiteral("no NFC adapter"));
        return;
    }
    if (m_writePending) {
        return;
    }

    m_writeUri = uri;
    m_writeShortUri = shortUri;
    m_writeTagPath.clear();
    m_writeImage.clear();
    m_writePending = true;
    setWriting(true);

    subscribeIfNeeded();
    m_writeTimeout->start();

    // Unlike the read path, a tag that is already on the reader is exactly
    // what we want here; ignoring a resting tag applies to reading only.
    foreach (const QString &adapter, m_adapters) {
        callAsync(kDaemonService, adapter, kIfaceAdapter,
                  QStringLiteral("GetTags"), QVariantList(),
                  SLOT(onWriteTagsReply(QDBusPendingCallWatcher*)), 5000, QString());
    }
}

void NfcManager::onWriteTagsReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    if (!m_writePending || !m_writeTagPath.isEmpty()) {
        return;
    }
    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        return;
    }
    const QStringList tags = reply.arguments().isEmpty()
            ? QStringList()
            : objectPathsFrom(reply.arguments().first());
    if (!tags.isEmpty()) {
        beginWrite(tags.first());
    }
}

void NfcManager::beginWrite(const QString &tagPath)
{
    m_writeTagPath = tagPath;
    emit writeStarted();

    // Acquire keeps nfcd from deactivating the tag between our calls.
    // ndef-write gets away without it because it is done in milliseconds; we
    // are not, so we ask -- but we do not insist, because older nfcd builds
    // may not offer Acquire2 at all.
    callAsync(kDaemonService, tagPath, kIfaceTag,
              QStringLiteral("Acquire2"), QVariantList() << QVariant(false),
              SLOT(onAcquireReply(QDBusPendingCallWatcher*)), 5000, tagPath);
}

void NfcManager::onAcquireReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();
    if (!m_writePending || tagPath != m_writeTagPath) {
        return;
    }

    const QDBusMessage reply = watcher->reply();
    m_tagAcquired = (reply.type() != QDBusMessage::ErrorMessage);
    if (!m_tagAcquired) {
        qDebug() << "[Nfc] Acquire2 unavailable, continuing without:"
                 << reply.errorMessage();
    }

    callAsync(kDaemonService, tagPath, kIfaceType2,
              QStringLiteral("ReadAllData"), QVariantList(),
              SLOT(onReadAllDataReply(QDBusPendingCallWatcher*)), 15000, tagPath);
}

void NfcManager::onReadAllDataReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();
    if (!m_writePending || tagPath != m_writeTagPath) {
        return;
    }

    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        const QString error = reply.errorName();
        // A tag without the TagType2 interface answers with UnknownMethod or
        // UnknownInterface -- that is a tag type we cannot write.
        if (error.contains(QStringLiteral("UnknownMethod"))
                || error.contains(QStringLiteral("UnknownInterface"))
                || error.contains(QStringLiteral("UnknownObject"))) {
            finishWrite(false, QStringLiteral("unsupportedTagType"), reply.errorMessage());
        } else {
            finishWrite(false, QStringLiteral("readFailed"), reply.errorMessage());
        }
        return;
    }

    const QByteArray current = reply.arguments().isEmpty()
            ? QByteArray()
            : byteArrayFrom(reply.arguments().first());
    if (current.isEmpty()) {
        finishWrite(false, QStringLiteral("readFailed"),
                    QStringLiteral("ReadAllData returned no data"));
        return;
    }

    // Long form first, short form as the fallback.
    QByteArray image = NfcCodec::buildTagImage(
                current, NfcCodec::buildUriMessage(m_writeUri));
    if (image.isEmpty() && !m_writeShortUri.isEmpty()) {
        qDebug() << "[Nfc] long URI does not fit, falling back to the short form";
        image = NfcCodec::buildTagImage(
                    current, NfcCodec::buildUriMessage(m_writeShortUri));
    }
    if (image.isEmpty()) {
        finishWrite(false, QStringLiteral("tagTooSmall"),
                    QStringLiteral("capacity %1 bytes")
                    .arg(NfcCodec::capacity(current)));
        return;
    }

    const int bytesToWrite = NfcCodec::changedPrefixLength(image, current);
    if (bytesToWrite == 0) {
        // The tag already holds exactly this content.
        finishWrite(true, QString(), QStringLiteral("nothing to write"));
        return;
    }

    m_writeImage = image;
    callAsync(kDaemonService, tagPath, kIfaceType2,
              QStringLiteral("WriteData"),
              QVariantList() << QVariant(uint(0))
                             << QVariant(image.left(bytesToWrite)),
              SLOT(onWriteDataReply(QDBusPendingCallWatcher*)), 15000, tagPath);
}

void NfcManager::onWriteDataReply(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    const QString tagPath = watcher->property("tagPath").toString();
    if (!m_writePending || tagPath != m_writeTagPath) {
        return;
    }

    const QDBusMessage reply = watcher->reply();
    if (reply.type() == QDBusMessage::ErrorMessage) {
        const QString error = reply.errorName();
        if (error.contains(QStringLiteral("UnknownObject"))) {
            finishWrite(false, QStringLiteral("tagRemoved"), reply.errorMessage());
        } else {
            // Covers write protection and lock bits, which nfcd reports as a
            // plain failure without a distinguishable error name.
            finishWrite(false, QStringLiteral("writeFailed"), reply.errorMessage());
        }
        return;
    }

    const uint written = reply.arguments().value(0).toUInt();
    qDebug() << "[Nfc] wrote" << written << "bytes to" << tagPath;
    finishWrite(true, QString(), QString());
}

void NfcManager::onWriteTimeout()
{
    if (!m_writePending) {
        return;
    }
    finishWrite(false, QStringLiteral("noTag"), QStringLiteral("timeout"));
}

void NfcManager::cancelWrite()
{
    if (!m_writePending) {
        return;
    }
    finishWrite(false, QStringLiteral("cancelled"), QString());
}

void NfcManager::suspendReading()
{
    m_readSuppression++;
    if (m_readSuppression == 1) {
        // Whatever is already on its way must not slip through either.
        m_inFlightTagPaths.clear();
        m_pendingReads.clear();
        qDebug() << "[Nfc] reading muted";
    }
}

void NfcManager::resumeReading()
{
    if (m_readSuppression == 0) {
        return;
    }
    m_readSuppression--;
    if (m_readSuppression == 0) {
        qDebug() << "[Nfc] reading unmuted";
        // The tag the user has just written is normally still lying on the
        // reader. Treat it like a tag that was already there when listening
        // started: it must not fire until it has been lifted and put back.
        if (m_listening) {
            ignoreCurrentTags();
        }
    }
}

void NfcManager::finishWrite(bool success, const QString &code, const QString &detail)
{
    m_writeTimeout->stop();

    if (!m_writeTagPath.isEmpty()) {
        releaseTag(m_writeTagPath);
        m_writeTagPath.clear();
    }
    m_writePending = false;
    m_writeUri.clear();
    m_writeShortUri.clear();
    m_writeImage.clear();
    setWriting(false);
    unsubscribeIfIdle();

    if (!success) {
        qWarning() << "[Nfc] write failed:" << code << detail;
    }
    emit writeFinished(success, code, detail);
}

void NfcManager::releaseTag(const QString &tagPath)
{
    if (!m_tagAcquired) {
        return;
    }
    m_tagAcquired = false;
    // Fire and forget: there is nothing useful to do if the release fails,
    // and nfcd drops the lock when our connection goes away anyway.
    QDBusMessage message = QDBusMessage::createMethodCall(
                kDaemonService, tagPath, kIfaceTag, QStringLiteral("Release2"));
    m_bus.asyncCall(message, 5000);
}

void NfcManager::setWriting(bool writing)
{
    if (m_writing == writing) {
        return;
    }
    m_writing = writing;
    emit writingChanged();
}
