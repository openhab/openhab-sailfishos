#ifndef SSEMANAGER_H
#define SSEMANAGER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class SSEManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
public:
    explicit SSEManager(QObject *parent = nullptr);
    ~SSEManager();

    bool isActive() const;

public slots:
    void connectToOpenHAB(const QString &baseUrl);
    void disconnectFromOpenHAB();

signals:
    void messageReceived(const QString &message);
    void statusChanged(const QString &status);
    void connected();
    void activeChanged();

private slots:
    void onReadyRead();
    void onFinished();
    void onErrorOccurred(QNetworkReply::NetworkError code);

private:
    QNetworkAccessManager m_nam;
    QNetworkReply *m_reply = nullptr;
    QString m_baseUrl;
    bool m_active = false;
    bool m_shouldReconnect = false;
};

#endif
