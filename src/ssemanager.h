#ifndef SSEMANAGER_H
#define SSEMANAGER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class SSEManager : public QObject
{
    Q_OBJECT
public:
    explicit SSEManager(QObject *parent = nullptr);
    ~SSEManager();

public slots:
    void connectToOpenHAB(const QString &baseUrl);

signals:
    void messageReceived(const QString &message);
    void statusChanged(const QString &status);
    void connected();

private slots:
    void onReadyRead();
    void onFinished();

private:
    QNetworkAccessManager m_nam;
    QNetworkReply *m_reply = nullptr;
    QString m_baseUrl;
};

#endif
