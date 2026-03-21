#include "ssemanager.h"
#include <QNetworkRequest>
#include <QDebug>
#include <QTimer>
#include <QUrl>

SSEManager::SSEManager(QObject *parent) : QObject(parent) {}

SSEManager::~SSEManager() {
    disconnectFromOpenHAB();
}

bool SSEManager::isActive() const {
    return m_active;
}

void SSEManager::connectToOpenHAB(const QString &baseUrl)
{
    // Cleanly close any existing connection
    if (m_reply) {
        m_shouldReconnect = false; // Prevent reconnect from onFinished
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = nullptr;
    }

    m_baseUrl = baseUrl;
    m_shouldReconnect = true;

    QUrl url(baseUrl + "/rest/events");
    QNetworkRequest request(url);
    request.setRawHeader("Accept", "text/event-stream");

    m_reply = m_nam.get(request);

    connect(m_reply, &QNetworkReply::readyRead, this, &SSEManager::onReadyRead);
    connect(m_reply, &QNetworkReply::finished, this, &SSEManager::onFinished);
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    connect(m_reply, &QNetworkReply::errorOccurred, this, &SSEManager::onErrorOccurred);
#else
    connect(m_reply, SIGNAL(error(QNetworkReply::NetworkError)),
            this, SLOT(onErrorOccurred(QNetworkReply::NetworkError)));
#endif

    emit statusChanged("Connecting...");
    qDebug() << "SSE connecting to:" << url.toString();
}

void SSEManager::disconnectFromOpenHAB()
{
    m_shouldReconnect = false;

    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = nullptr;
    }

    if (m_active) {
        m_active = false;
        emit activeChanged();
    }

    emit statusChanged("Disconnected");
    qDebug() << "SSE disconnected.";
}

void SSEManager::onReadyRead()
{
    // Transition to active on first successful data received
    if (!m_active) {
        m_active = true;
        emit activeChanged();
        emit statusChanged("SSE Streaming...");
        emit connected();
        qDebug() << "SSE stream established.";
    }

    while (m_reply && m_reply->canReadLine()) {
        QByteArray line = m_reply->readLine().trimmed();

        if (line.startsWith("data: ")) {
            QString jsonPayload = QString::fromUtf8(line.mid(6));
            emit messageReceived(jsonPayload);
        }
    }
}

void SSEManager::onFinished()
{
    // Clean up the finished reply immediately
    if (m_reply) {
        m_reply->deleteLater();
        m_reply = nullptr;
    }

    if (!m_shouldReconnect) {
        qDebug() << "SSE Stream closed. No reconnect requested.";
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        emit statusChanged("Disconnected");
        return;
    }

    qDebug() << "SSE Stream closed. Reconnecting in 5s...";
    if (m_active) {
        m_active = false;
        emit activeChanged();
    }
    emit statusChanged("Reconnecting...");

    // Capture baseUrl by value to avoid depending on stale member state
    QString reconnectUrl = m_baseUrl;
    QTimer::singleShot(5000, this, [this, reconnectUrl]() {
        if (m_shouldReconnect) {
            connectToOpenHAB(reconnectUrl);
        }
    });
}

void SSEManager::onErrorOccurred(QNetworkReply::NetworkError code)
{
    // OperationCanceledError is expected when we abort the reply ourselves
    if (code == QNetworkReply::OperationCanceledError)
        return;

    qWarning() << "SSE network error:" << code
               << (m_reply ? m_reply->errorString() : QString());

    if (m_active) {
        m_active = false;
        emit activeChanged();
    }

    emit statusChanged("Error: " + (m_reply ? m_reply->errorString() : QStringLiteral("Unknown")));
}

