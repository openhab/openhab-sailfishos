#ifndef REMOTEAUTH_H
#define REMOTEAUTH_H

#include <QByteArray>
#include <QNetworkAccessManager>
#include <QQmlNetworkAccessManagerFactory>
#include <QString>
#include <QUrl>

/**
 * Credentials of the remote server (openHAB Cloud) for requests that QML
 * makes on its own: Image { source: ".../icon/..." }, charts, image widgets.
 * Those cannot set an Authorization header, and myopenhab.org answers them
 * with 401 otherwise.
 *
 * The header is only added for exactly the configured origin (scheme, host
 * and port), and only when the request does not carry one already, so the
 * local server and third-party URLs in sitemaps never see these
 * credentials.
 *
 * Thread-safe: QML creates network access managers on loader threads.
 */
class RemoteAuth
{
public:
    static void set(const QString &origin, const QByteArray &authHeader);
    static void clear();
    /** Header for this URL, or an empty array when it is not the remote origin. */
    static QByteArray headerFor(const QUrl &url);
};

class RemoteAuthNetworkAccessManager : public QNetworkAccessManager
{
    Q_OBJECT
public:
    explicit RemoteAuthNetworkAccessManager(QObject *parent = nullptr)
        : QNetworkAccessManager(parent) {}

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request,
                                 QIODevice *outgoingData = nullptr) override;
};

class RemoteAuthNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        return new RemoteAuthNetworkAccessManager(parent);
    }
};

#endif // REMOTEAUTH_H
