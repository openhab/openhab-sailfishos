#include "remoteauth.h"
#include "connectionmanager.h"

#include <QMutex>
#include <QMutexLocker>
#include <QNetworkRequest>

namespace {
QMutex s_mutex;
QString s_origin;
QByteArray s_header;
}

void RemoteAuth::set(const QString &origin, const QByteArray &authHeader)
{
    QMutexLocker lock(&s_mutex);
    s_origin = origin;
    s_header = authHeader;
}

void RemoteAuth::clear()
{
    QMutexLocker lock(&s_mutex);
    s_origin.clear();
    s_header.clear();
}

QByteArray RemoteAuth::headerFor(const QUrl &url)
{
    const QString origin = ConnectionManager::originOf(url.toString());
    QMutexLocker lock(&s_mutex);
    if (s_origin.isEmpty() || origin != s_origin) return QByteArray();
    return s_header;
}

QNetworkReply *RemoteAuthNetworkAccessManager::createRequest(Operation op,
                                                             const QNetworkRequest &request,
                                                             QIODevice *outgoingData)
{
    if (!request.hasRawHeader("Authorization")) {
        const QByteArray header = RemoteAuth::headerFor(request.url());
        if (!header.isEmpty()) {
            QNetworkRequest withAuth(request);
            withAuth.setRawHeader("Authorization", header);
            return QNetworkAccessManager::createRequest(op, withAuth, outgoingData);
        }
    }
    return QNetworkAccessManager::createRequest(op, request, outgoingData);
}
