#ifndef CONNECTIONMANAGER_H
#define CONNECTIONMANAGER_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkConfigurationManager>

class QNetworkReply;

/**
 * Picks the connection the app talks to: the local openHAB server or the
 * remote one (openHAB Cloud, e.g. myopenhab.org).
 *
 * Without a remote server configured nothing is probed at all -- the local
 * URL is used exactly as before, so existing setups behave unchanged.
 *
 * With a remote server, both are probed in parallel (GET <url>/rest/). Local
 * wins whenever it answers; remote is only taken once local has failed or a
 * short grace period has passed (pattern of the iOS NetworkTracker). The
 * choice is re-evaluated on network changes and whenever QML calls refresh(),
 * e.g. when the app comes back to the foreground.
 *
 * QML reads baseUrl/username/password of the *active* connection, so call
 * sites do not need to know which one it is.
 */
class ConnectionManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY activeChanged)
    Q_PROPERTY(QString username READ username NOTIFY activeChanged)
    Q_PROPERTY(QString password READ password NOTIFY activeChanged)
    // Main UI address. Remote: the cloud's proxy host from /api/v1/proxyurl
    // ("url", e.g. home.myopenhab.org; myopenhab.org itself only shows the
    // cloud website), falling back to the remote URL. It asks for Basic
    // auth, which MainUiPage answers with the remote credentials. The
    // browser host ("browserUrl", connect.*) is not used: it needs the
    // cloud's login form and the Main UI stayed black there.
    Q_PROPERTY(QString mainUiUrl READ mainUiUrl NOTIFY activeChanged)
    // "local" | "remote" | "none" (nothing reachable)
    Q_PROPERTY(QString type READ type NOTIFY activeChanged)
    Q_PROPERTY(bool remoteConfigured READ remoteConfigured NOTIFY configChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(bool testing READ testing NOTIFY testingChanged)

public:
    // Probe results, also reported to QML by testConnections().
    enum ProbeResult {
        Ok,
        OkNoCloud,      // remote answers, but is not an openHAB Cloud
        Network,        // not reachable / timeout
        Unauthorized,   // 401/403
        Offline,        // cloud reachable, but the openHAB server behind it is not connected
        NotOpenHab,     // something answered, but not openHAB's REST API
        HttpError
    };
    Q_ENUM(ProbeResult)

    explicit ConnectionManager(QObject *parent = nullptr);

    QString baseUrl() const { return m_activeUrl; }
    QString username() const { return m_activeUser; }
    QString password() const { return m_activePassword; }
    QString type() const { return m_type; }
    QString mainUiUrl() const;
    bool remoteConfigured() const;
    bool checking() const { return m_checking; }
    bool testing() const { return m_testing; }

    /** Set both connections. Passwords in plain text (already decoded). */
    Q_INVOKABLE void configure(const QString &localUrl, const QString &localUser,
                               const QString &localPassword,
                               bool remoteEnabled, const QString &remoteUrl,
                               const QString &remoteUser, const QString &remotePassword);

    /** Re-evaluate which connection to use. Cheap no-op without remote. */
    Q_INVOKABLE void refresh();

    /** Delay before retry number `attempt` (0-based), -1 when out of retries. */
    static int retryDelayMs(int attempt, bool allFailed);

    /**
     * App in the foreground or not. While in the foreground and connected
     * remotely, the local server is checked again now and then, so coming
     * home switches back to it even if no network event says so.
     */
    Q_INVOKABLE void setForeground(bool foreground);

    /** Unit tests only: give up right away instead of retrying. */
    void setRetriesEnabled(bool enabled) { m_retriesEnabled = enabled; }

    /**
     * Probe the given values (e.g. the unsaved fields of the settings page)
     * independently of the active connection. Emits testFinished().
     * An empty URL skips that side (result "skipped").
     */
    Q_INVOKABLE void testConnections(const QString &localUrl, const QString &localUser,
                                     const QString &localPassword,
                                     const QString &remoteUrl, const QString &remoteUser,
                                     const QString &remotePassword);

    // ── Pure helpers, public for the unit tests ──
    static QString normalizeUrl(const QString &url);
    /** "https://myopenhab.org:443" style key used to match requests to a server. */
    static QString originOf(const QString &url);
    static QByteArray basicAuth(const QString &user, const QString &password);
    /** Classify the answer to GET <url>/rest/. */
    static ProbeResult classifyRestProbe(int httpStatus, bool networkError,
                                         const QByteArray &body, bool isLocal);
    static QString resultName(ProbeResult result);

signals:
    void activeChanged();
    void configChanged();
    void checkingChanged();
    void testingChanged();
    /** localResult/remoteResult: resultName() values or "skipped". */
    void testFinished(const QString &localResult, const QString &remoteResult);

private slots:
    void onNetworkChanged();
    void onNetworkSettled();
    void onGraceExpired();
    void probe();

private:
    struct Endpoint {
        QString url;
        QString user;
        QString password;
    };

    QNetworkReply *startGet(QNetworkAccessManager *nam, const Endpoint &ep,
                            const QString &path, int timeoutMs);
    void renewNetworkAccess();
    void updateLocalRecheck();
    void onProbeFinished(QNetworkReply *reply, bool isLocal, int generation);
    void decide();
    void setActive(const QString &type);
    void setChecking(bool checking);
    void abortProbes();
    bool scheduleRetry(bool allFailed);
    bool usingRemote() const;
    void publishRemoteAuth();
    void finishTestIfDone();
    void fetchProxyUrl();

    // Probes and proxy URL. Replaced after network changes: Qt 5.6 keeps a
    // QNAM bound to the network session it started on, and requests to the
    // local server then hang after rejoining Wi-Fi.
    QNetworkAccessManager *m_nam = nullptr;
    // Connection test, separate so renewing m_nam never kills a running test.
    QNetworkAccessManager m_testNam;
    QTimer m_localRecheck;
    bool m_foreground = true;
    QNetworkConfigurationManager m_netConfig;
    QTimer m_networkDebounce;
    QTimer m_graceTimer;
    QTimer m_retryTimer;
    int m_retryAttempt = 0;
    bool m_retriesEnabled = true;
    // Next probe only re-checks local while remote works: no "checking" state.
    bool m_quietRetry = false;
    // Set after a network change: a local server that is not reachable yet
    // (Wi-Fi still getting its address) is checked again a few times.
    bool m_retryLocal = false;
    QString m_netFingerprint;

    Endpoint m_local;
    Endpoint m_remote;
    bool m_remoteEnabled = false;

    QString m_activeUrl;
    QString m_activeUser;
    QString m_activePassword;
    QString m_type = QStringLiteral("local");
    // Last reachable connection; "none" keeps its address so pages are not
    // pointed at a server that was never the one in use.
    QString m_lastReachable = QStringLiteral("local");
    QString m_remoteProxyUrl;
    int m_proxyUrlGeneration = 0;
    bool m_proxyUrlSettled = false;
    bool m_proxyUrlInFlight = false;
    bool m_checking = false;

    // Current probe round
    int m_generation = 0;
    QNetworkReply *m_localReply = nullptr;
    QNetworkReply *m_remoteReply = nullptr;
    bool m_localDone = false;
    bool m_remoteDone = false;
    bool m_localOk = false;
    bool m_remoteOk = false;

    // Connection test (settings page)
    bool m_testing = false;
    int m_testGeneration = 0;
    int m_testPending = 0;
    QString m_testLocalResult;
    QString m_testRemoteResult;
};

#endif // CONNECTIONMANAGER_H
