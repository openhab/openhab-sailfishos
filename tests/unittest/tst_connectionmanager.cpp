/*
 * Unit tests for ConnectionManager (local/remote selection, connection test)
 * and RemoteAuth (credential injection for QML's own requests).
 *
 * The network tests run against small HTTP servers on 127.0.0.1, so they need
 * no internet access. Should the build host refuse even loopback requests,
 * they are skipped instead of failing the build.
 */

#include <QtTest>
#include <QHash>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>

#include "cloud/connectionmanager.h"
#include "cloud/remoteauth.h"

// ── Minimal HTTP server ─────────────────────────────────────────────

class MockHttpServer : public QObject
{
    Q_OBJECT
public:
    struct Response { int status = 404; QByteArray body; int delayMs = 0; };

    explicit MockHttpServer(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&m_server, &QTcpServer::newConnection, this, &MockHttpServer::onNewConnection);
        m_server.listen(QHostAddress::LocalHost, 0);
    }

    QString url() const { return QStringLiteral("http://127.0.0.1:%1").arg(m_server.serverPort()); }

    void on(const QString &path, int status, const QByteArray &body = QByteArray(), int delayMs = 0)
    {
        Response r; r.status = status; r.body = body; r.delayMs = delayMs;
        m_routes.insert(path, r);
    }

    QHash<QString, QByteArray> authByPath;   // last Authorization header per path

private slots:
    void onNewConnection()
    {
        while (QTcpSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
                m_buffers[socket] += socket->readAll();
                const QByteArray &buf = m_buffers[socket];
                if (!buf.contains("\r\n\r\n")) return;
                handle(socket, buf);
            });
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        }
    }

private:
    void handle(QTcpSocket *socket, const QByteArray &request)
    {
        const QList<QByteArray> lines = request.split('\n');
        const QList<QByteArray> first = lines.value(0).trimmed().split(' ');
        const QString path = QString::fromLatin1(first.value(1));
        for (const QByteArray &line : lines) {
            if (line.toLower().startsWith("authorization:")) {
                authByPath.insert(path, line.mid(14).trimmed());
            }
        }
        const Response r = m_routes.value(path);
        auto send = [socket, r]() {
            QByteArray out = "HTTP/1.1 " + QByteArray::number(r.status) + " X\r\n"
                    "Content-Type: application/json\r\n"
                    "Content-Length: " + QByteArray::number(r.body.size()) + "\r\n"
                    "Connection: close\r\n\r\n" + r.body;
            socket->write(out);
            socket->disconnectFromHost();
        };
        if (r.delayMs > 0) QTimer::singleShot(r.delayMs, socket, send);
        else send();
    }

    QTcpServer m_server;
    QHash<QString, Response> m_routes;
    QHash<QTcpSocket *, QByteArray> m_buffers;
};

static const QByteArray kRestRoot = "{\"version\":\"8\",\"links\":[]}";

/** A URL on which nothing listens: connection refused right away. */
static QString closedPortUrl()
{
    QTcpServer server;
    server.listen(QHostAddress::LocalHost, 0);
    const quint16 port = server.serverPort();
    server.close();
    return QStringLiteral("http://127.0.0.1:%1").arg(port);
}

static bool waitUntilNotChecking(ConnectionManager &cm, int timeoutMs = 8000)
{
    QElapsedTimer timer; timer.start();
    // The first round starts synchronously in configure(); give it a moment.
    while (timer.elapsed() < timeoutMs) {
        QTest::qWait(50);
        if (!cm.checking()) return true;
    }
    return false;
}

class tst_ConnectionManager : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();

    // Pure helpers
    void normalizeUrl_data();
    void normalizeUrl();
    void originOf_data();
    void originOf();
    void basicAuth();
    void classifyRestProbe_data();
    void classifyRestProbe();

    // RemoteAuth
    void remoteAuth_onlyForConfiguredOrigin();
    void remoteAuth_clear();

    // Selection
    void noRemote_usesLocalWithoutProbing();
    void localReachable_winsOverRemote();
    void localDown_usesRemote();
    void bothDown_none();
    void bothDown_retriesBeforeNone();
    void retryDelays();
    void remoteFaster_graceKeepsLocal();
    void probe_sendsCredentials();
    void remoteDisabled_fallsBackToLocal();
    void mainUiUrl_fromProxyUrl();

    // Connection test
    void test_cloudOk();
    void test_notACloud();
    void test_unauthorized();
    void test_cloudButOpenHabOffline();
    void test_emptyUrlsAreSkipped();

private:
    bool m_networkUsable = true;
};

void tst_ConnectionManager::initTestCase()
{
    // Some build hosts have no usable network configuration at all, in which
    // case QNetworkAccessManager refuses even loopback requests.
    MockHttpServer server;
    server.on("/ping", 200, "{}");
    QNetworkAccessManager nam;
    QNetworkReply *reply = nam.get(QNetworkRequest(QUrl(server.url() + "/ping")));
    QSignalSpy spy(reply, &QNetworkReply::finished);
    spy.wait(3000);
    m_networkUsable = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200;
    reply->deleteLater();
    if (!m_networkUsable) {
        qWarning("Loopback HTTP not usable here - network tests will be skipped");
    }
}

#define REQUIRE_NETWORK() \
    if (!m_networkUsable) QSKIP("loopback HTTP not available on this host")

// ── Pure helpers ────────────────────────────────────────────────────

void tst_ConnectionManager::normalizeUrl_data()
{
    QTest::addColumn<QString>("in");
    QTest::addColumn<QString>("out");
    QTest::newRow("plain") << "https://myopenhab.org" << "https://myopenhab.org";
    QTest::newRow("trailing") << "https://myopenhab.org///" << "https://myopenhab.org";
    QTest::newRow("single slash") << "https:/myopenhab.org" << "https://myopenhab.org";
    QTest::newRow("http single") << "http:/192.168.1.2:8080/" << "http://192.168.1.2:8080";
    QTest::newRow("whitespace") << "  https://a.b  " << "https://a.b";
    QTest::newRow("empty") << "" << "";
}

void tst_ConnectionManager::normalizeUrl()
{
    QFETCH(QString, in);
    QFETCH(QString, out);
    QCOMPARE(ConnectionManager::normalizeUrl(in), out);
}

void tst_ConnectionManager::originOf_data()
{
    QTest::addColumn<QString>("url");
    QTest::addColumn<QString>("origin");
    QTest::newRow("https default") << "https://MyOpenHAB.org/icon/x" << "https://myopenhab.org:443";
    QTest::newRow("https explicit") << "https://myopenhab.org:443" << "https://myopenhab.org:443";
    QTest::newRow("http default") << "http://host/rest" << "http://host:80";
    QTest::newRow("custom port") << "http://192.168.1.2:8080/rest" << "http://192.168.1.2:8080";
    QTest::newRow("no host") << "not a url" << "";
}

void tst_ConnectionManager::originOf()
{
    QFETCH(QString, url);
    QFETCH(QString, origin);
    QCOMPARE(ConnectionManager::originOf(url), origin);
}

void tst_ConnectionManager::basicAuth()
{
    QCOMPARE(ConnectionManager::basicAuth("user", "pass"), QByteArray("Basic dXNlcjpwYXNz"));
}

void tst_ConnectionManager::classifyRestProbe_data()
{
    QTest::addColumn<int>("status");
    QTest::addColumn<bool>("netError");
    QTest::addColumn<QByteArray>("body");
    QTest::addColumn<bool>("isLocal");
    QTest::addColumn<int>("expected");

    QTest::newRow("ok") << 200 << false << kRestRoot << true << int(ConnectionManager::Ok);
    QTest::newRow("ok remote") << 200 << false << kRestRoot << false << int(ConnectionManager::Ok);
    QTest::newRow("captive portal") << 200 << false << QByteArray("<html>login</html>") << true
                                    << int(ConnectionManager::NotOpenHab);
    QTest::newRow("json but not openHAB") << 200 << false << QByteArray("{\"a\":1}") << true
                                          << int(ConnectionManager::NotOpenHab);
    QTest::newRow("401") << 401 << true << QByteArray() << false << int(ConnectionManager::Unauthorized);
    QTest::newRow("403") << 403 << true << QByteArray() << true << int(ConnectionManager::Unauthorized);
    QTest::newRow("refused") << 0 << true << QByteArray() << true << int(ConnectionManager::Network);
    QTest::newRow("cloud offline") << 500 << true << QByteArray("openHAB is offline") << false
                                   << int(ConnectionManager::Offline);
    QTest::newRow("local 500") << 500 << true << QByteArray() << true << int(ConnectionManager::HttpError);
    QTest::newRow("404") << 404 << true << QByteArray() << false << int(ConnectionManager::HttpError);
}

void tst_ConnectionManager::classifyRestProbe()
{
    QFETCH(int, status);
    QFETCH(bool, netError);
    QFETCH(QByteArray, body);
    QFETCH(bool, isLocal);
    QFETCH(int, expected);
    QCOMPARE(int(ConnectionManager::classifyRestProbe(status, netError, body, isLocal)), expected);
}

// ── RemoteAuth ──────────────────────────────────────────────────────

void tst_ConnectionManager::remoteAuth_onlyForConfiguredOrigin()
{
    RemoteAuth::set("https://myopenhab.org:443", "Basic abc");
    QCOMPARE(RemoteAuth::headerFor(QUrl("https://myopenhab.org/icon/light?format=svg")),
             QByteArray("Basic abc"));
    QCOMPARE(RemoteAuth::headerFor(QUrl("https://MYOPENHAB.org:443/chart")), QByteArray("Basic abc"));
    // Different scheme, port or host: never.
    QVERIFY(RemoteAuth::headerFor(QUrl("http://myopenhab.org/icon/x")).isEmpty());
    QVERIFY(RemoteAuth::headerFor(QUrl("https://myopenhab.org:8443/icon/x")).isEmpty());
    QVERIFY(RemoteAuth::headerFor(QUrl("https://evil.example/icon/x")).isEmpty());
    QVERIFY(RemoteAuth::headerFor(QUrl("https://myopenhab.org.evil.example/")).isEmpty());
    RemoteAuth::clear();
}

void tst_ConnectionManager::remoteAuth_clear()
{
    RemoteAuth::set("https://myopenhab.org:443", "Basic abc");
    RemoteAuth::clear();
    QVERIFY(RemoteAuth::headerFor(QUrl("https://myopenhab.org/icon/x")).isEmpty());
}

// ── Selection ───────────────────────────────────────────────────────

void tst_ConnectionManager::noRemote_usesLocalWithoutProbing()
{
    ConnectionManager cm;
    cm.configure("http://192.168.1.2:8080/", "u", "p", false, "https://myopenhab.org", "r", "rp");
    QCOMPARE(cm.type(), QString("local"));
    QCOMPARE(cm.baseUrl(), QString("http://192.168.1.2:8080"));
    QCOMPARE(cm.username(), QString("u"));
    QCOMPARE(cm.password(), QString("p"));
    QVERIFY(!cm.checking());
    QVERIFY(!cm.remoteConfigured());
    // Old behaviour must not change: no credentials handed out for QML requests.
    QVERIFY(RemoteAuth::headerFor(QUrl("https://myopenhab.org/icon/x")).isEmpty());
}

void tst_ConnectionManager::localReachable_winsOverRemote()
{
    REQUIRE_NETWORK();
    MockHttpServer local, remote;
    local.on("/rest/", 200, kRestRoot);
    remote.on("/rest/", 200, kRestRoot);

    ConnectionManager cm;
    cm.configure(local.url(), "", "", true, remote.url(), "r@x", "rp");
    QVERIFY(cm.remoteConfigured());
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("local"));
    QCOMPARE(cm.baseUrl(), local.url());
}

void tst_ConnectionManager::localDown_usesRemote()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 200, kRestRoot);

    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::activeChanged);
    cm.configure(closedPortUrl(), "", "", true, remote.url(), "r@x", "rp");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("remote"));
    QCOMPARE(cm.baseUrl(), remote.url());
    QCOMPARE(cm.username(), QString("r@x"));
    QCOMPARE(cm.password(), QString("rp"));
    QVERIFY(spy.count() > 0);
}

void tst_ConnectionManager::bothDown_none()
{
    REQUIRE_NETWORK();
    ConnectionManager cm;
    cm.setRetriesEnabled(false);
    const QString localUrl = closedPortUrl();
    cm.configure(localUrl, "", "", true, closedPortUrl(), "r@x", "rp");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("none"));
    // Errors then come from the last reachable (here: local) server.
    QCOMPARE(cm.baseUrl(), localUrl);
}

void tst_ConnectionManager::bothDown_retriesBeforeNone()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 500, "openHAB is offline");

    ConnectionManager cm;
    cm.configure(closedPortUrl(), "", "", true, remote.url(), "r@x", "rp");
    // First round failed, but it keeps checking instead of reporting "none".
    QTest::qWait(500);
    QVERIFY(cm.checking());
    QVERIFY(cm.type() != QString("none"));

    // Server comes back: picked up by the next retry.
    remote.on("/rest/", 200, kRestRoot);
    QTRY_COMPARE_WITH_TIMEOUT(cm.type(), QString("remote"), 5000);
    QVERIFY(!cm.checking());
}

void tst_ConnectionManager::retryDelays()
{
    QVERIFY(ConnectionManager::retryDelayMs(0, true) > 0);
    QCOMPARE(ConnectionManager::retryDelayMs(-1, true), -1);
    QCOMPARE(ConnectionManager::retryDelayMs(100, true), -1);
    // Re-checking only local gives up earlier than when nothing works.
    int all = 0, localOnly = 0;
    while (ConnectionManager::retryDelayMs(all, true) > 0) ++all;
    while (ConnectionManager::retryDelayMs(localOnly, false) > 0) ++localOnly;
    QVERIFY(localOnly > 0);
    QVERIFY(localOnly < all);
}

void tst_ConnectionManager::remoteFaster_graceKeepsLocal()
{
    REQUIRE_NETWORK();
    MockHttpServer local, remote;
    local.on("/rest/", 200, kRestRoot, 400);   // slower, but within the grace period
    remote.on("/rest/", 200, kRestRoot);

    ConnectionManager cm;
    cm.configure(local.url(), "", "", true, remote.url(), "r@x", "rp");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("local"));
}

void tst_ConnectionManager::probe_sendsCredentials()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 200, kRestRoot);

    ConnectionManager cm;
    cm.configure(closedPortUrl(), "", "", true, remote.url(), "user", "pass");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(remote.authByPath.value("/rest/"), QByteArray("Basic dXNlcjpwYXNz"));
    // And QML's own requests to that server get the same header.
    QCOMPARE(RemoteAuth::headerFor(QUrl(remote.url() + "/icon/light")),
             QByteArray("Basic dXNlcjpwYXNz"));
}

void tst_ConnectionManager::remoteDisabled_fallsBackToLocal()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 200, kRestRoot);

    ConnectionManager cm;
    const QString localUrl = closedPortUrl();
    cm.configure(localUrl, "", "", true, remote.url(), "r@x", "rp");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("remote"));

    cm.configure(localUrl, "", "", false, remote.url(), "r@x", "rp");
    QCOMPARE(cm.type(), QString("local"));
    QCOMPARE(cm.baseUrl(), localUrl);
    QVERIFY(RemoteAuth::headerFor(QUrl(remote.url() + "/icon/light")).isEmpty());
}

void tst_ConnectionManager::mainUiUrl_fromProxyUrl()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 200, kRestRoot);
    remote.on("/api/v1/proxyurl", 200,
              "{\"url\":\"https://home.example\",\"browserUrl\":\"https://browser.example/\"}");

    ConnectionManager cm;
    cm.configure(closedPortUrl(), "", "", true, remote.url(), "r@x", "rp");
    QVERIFY(waitUntilNotChecking(cm));
    QCOMPARE(cm.type(), QString("remote"));
    // "url" (Basic auth), not "browserUrl" (cloud login form).
    QTRY_COMPARE_WITH_TIMEOUT(cm.mainUiUrl(), QString("https://home.example"), 5000);
    // REST stays on the configured remote URL.
    QCOMPARE(cm.baseUrl(), remote.url());
}

// ── Connection test ─────────────────────────────────────────────────

void tst_ConnectionManager::test_cloudOk()
{
    REQUIRE_NETWORK();
    MockHttpServer local, remote;
    local.on("/rest/", 200, kRestRoot);
    remote.on("/rest/", 200, kRestRoot);
    remote.on("/api/v1/settings/notifications", 200, "{}");

    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::testFinished);
    cm.testConnections(local.url(), "", "", remote.url(), "r@x", "rp");
    QVERIFY(spy.wait(8000));
    QCOMPARE(spy.at(0).at(0).toString(), QString("ok"));
    QCOMPARE(spy.at(0).at(1).toString(), QString("ok"));
    QVERIFY(!cm.testing());
}

void tst_ConnectionManager::test_notACloud()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 200, kRestRoot);
    remote.on("/api/v1/settings/notifications", 404);

    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::testFinished);
    cm.testConnections("", "", "", remote.url(), "r@x", "rp");
    QVERIFY(spy.wait(8000));
    QCOMPARE(spy.at(0).at(0).toString(), QString("skipped"));
    QCOMPARE(spy.at(0).at(1).toString(), QString("okNoCloud"));
}

void tst_ConnectionManager::test_unauthorized()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 401);
    remote.on("/api/v1/settings/notifications", 401);

    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::testFinished);
    cm.testConnections("", "", "", remote.url(), "r@x", "wrong");
    QVERIFY(spy.wait(8000));
    QCOMPARE(spy.at(0).at(1).toString(), QString("unauthorized"));
}

void tst_ConnectionManager::test_cloudButOpenHabOffline()
{
    REQUIRE_NETWORK();
    MockHttpServer remote;
    remote.on("/rest/", 500, "openHAB is offline");
    remote.on("/api/v1/settings/notifications", 200, "{}");

    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::testFinished);
    cm.testConnections("", "", "", remote.url(), "r@x", "rp");
    QVERIFY(spy.wait(8000));
    QCOMPARE(spy.at(0).at(1).toString(), QString("offline"));
}

void tst_ConnectionManager::test_emptyUrlsAreSkipped()
{
    ConnectionManager cm;
    QSignalSpy spy(&cm, &ConnectionManager::testFinished);
    cm.testConnections("", "", "", "", "", "");
    QCOMPARE(spy.count(), 1);
    QCOMPARE(spy.at(0).at(0).toString(), QString("skipped"));
    QCOMPARE(spy.at(0).at(1).toString(), QString("skipped"));
    QVERIFY(!cm.testing());
}

QTEST_MAIN(tst_ConnectionManager)
#include "tst_connectionmanager.moc"
