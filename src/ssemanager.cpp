#include "ssemanager.h"
#include <QNetworkRequest>
#include <QDebug>
#include <QTimer>
#include <QUrl>

SSEManager::SSEManager(QObject *parent) : QObject(parent) {}

SSEManager::~SSEManager() {
    if (m_reply) m_reply->abort();
}

void SSEManager::connectToOpenHAB(const QString &baseUrl)
{
    m_baseUrl = baseUrl;
    QUrl url(baseUrl + "/rest/events");

    QNetworkRequest request(url);
    request.setRawHeader("Accept", "text/event-stream");

    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
    }

    m_reply = m_nam.get(request);

    connect(m_reply, &QNetworkReply::readyRead, this, &SSEManager::onReadyRead);
    connect(m_reply, &QNetworkReply::finished, this, &SSEManager::onFinished);

    emit statusChanged("SSE Streaming...");
    emit connected(); // <-- HIER das neue Signal auslösen
}

void SSEManager::onReadyRead()
{
    while (m_reply && m_reply->canReadLine()) {
        QByteArray line = m_reply->readLine().trimmed();

        if (line.startsWith("data: ")) {
            QString jsonPayload = QString::fromUtf8(line.mid(6));
            // Wir leiten das JSON direkt an das QML handlMessage weiter
            emit messageReceived(jsonPayload);
        }
    }
}

void SSEManager::onFinished()
{
    qDebug() << "SSE Stream closed. Reconnecting...";
    emit statusChanged("Disconnected");
    // Automatischer Reconnect nach 5 Sekunden
    QTimer::singleShot(5000, this, [this]() { connectToOpenHAB(m_baseUrl); });
}
