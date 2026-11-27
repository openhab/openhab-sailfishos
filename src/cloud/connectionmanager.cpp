#include "connectionmanager.h"
#include "remoteauth.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkConfiguration>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSharedPointer>
#include <QStringList>
#include <QUrl>

namespace {
// Probe timeouts and grace period for the local server.
const int kLocalTimeoutMs = 3000;
const int kRemoteTimeoutMs = 10000;
const int kLocalGraceMs = 1000;
// Network events often come in bursts (Wi-Fi drops, mobile data comes up).
const int kNetworkDebounceMs = 2000;
// While switching networks, both servers are often unreachable for a few
// seconds (Wi-Fi gone, mobile data not up yet). Retry before giving up.
const int kRetryDelaysMs[] = { 1000, 2000, 3000, 5000, 8000, 12000 };
const int kRetryCount = sizeof(kRetryDelaysMs) / sizeof(kRetryDelaysMs[0]);
// Remote works, local did not answer right after a network change: check
// local a few more times (rejoined home Wi-Fi, address not there yet).
const int kLocalRetryCount = 3;
// In the foreground on remote: look for the local server this often.
const int kLocalRecheckMs = 30000;
}

ConnectionManager::ConnectionManager(QObject *parent)
    : QObject(parent)
{
    m_networkDebounce.setSingleShot(true);
    m_networkDebounce.setInterval(kNetworkDebounceMs);
    connect(&m_networkDebounce, &QTimer::timeout, this, &ConnectionManager::onNetworkSettled);

    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, &ConnectionManager::probe);

    m_nam = new QNetworkAccessManager(this);

    m_localRecheck.setInterval(kLocalRecheckMs);
    connect(&m_localRecheck, &QTimer::timeout, this, [this]() {
        if (m_checking) return;
        // Quiet: remote stays shown while local is looked for.
        m_quietRetry = true;
        probe();
    });

    m_graceTimer.setSingleShot(true);
    m_graceTimer.setInterval(kLocalGraceMs);
    connect(&m_graceTimer, &QTimer::timeout, this, &ConnectionManager::onGraceExpired);

    connect(&m_netConfig, &QNetworkConfigurationManager::onlineStateChanged,
            this, &ConnectionManager::onNetworkChanged);
    connect(&m_netConfig, &QNetworkConfigurationManager::configurationChanged,
            this, &ConnectionManager::onNetworkChanged);
    onNetworkChanged();   // remember the current state as baseline
}

bool ConnectionManager::remoteConfigured() const
{
    return m_remoteEnabled && !m_remote.url.isEmpty();
}

// ── Configuration ───────────────────────────────────────────────────

void ConnectionManager::configure(const QString &localUrl, const QString &localUser,
                                  const QString &localPassword,
                                  bool remoteEnabled, const QString &remoteUrl,
                                  const QString &remoteUser, const QString &remotePassword)
{
    Endpoint local { normalizeUrl(localUrl), localUser, localPassword };
    Endpoint remote { normalizeUrl(remoteUrl), remoteUser, remotePassword };

    const bool wasConfigured = remoteConfigured();
    const bool changed = local.url != m_local.url || local.user != m_local.user
            || local.password != m_local.password
            || remote.url != m_remote.url || remote.user != m_remote.user
            || remote.password != m_remote.password
            || remoteEnabled != m_remoteEnabled;

    const bool remoteChanged = remote.url != m_remote.url || remote.user != m_remote.user
            || remote.password != m_remote.password || remoteEnabled != m_remoteEnabled;

    m_local = local;
    m_remote = remote;
    m_remoteEnabled = remoteEnabled;
    publishRemoteAuth();

    if (remoteChanged) {
        // Fetched again by the refresh() below.
        m_remoteProxyUrl.clear();
        m_proxyUrlSettled = false;
        ++m_proxyUrlGeneration;
        m_proxyUrlInFlight = false;
    }

    if (wasConfigured != remoteConfigured()) {
        emit configChanged();
    }

    // Pick up new values for the connection in use right away, so a changed
    // password does not wait for the probe round.
    if (m_type != QLatin1String("local") && !remoteConfigured()) {
        setActive(QStringLiteral("local"));
    } else {
        setActive(m_type);
    }

    if (changed || m_generation == 0) {
        refresh();
    }
}

QString ConnectionManager::mainUiUrl() const
{
    if (usingRemote() && !m_remoteProxyUrl.isEmpty()) {
        return m_remoteProxyUrl;
    }
    return m_activeUrl;
}

bool ConnectionManager::usingRemote() const
{
    return m_type != QLatin1String("local") && remoteConfigured()
            && m_activeUrl == m_remote.url;
}

void ConnectionManager::fetchProxyUrl()
{
    const int generation = ++m_proxyUrlGeneration;
    if (!remoteConfigured()) return;
    m_proxyUrlInFlight = true;
    QNetworkReply *reply = startGet(m_nam, m_remote, QStringLiteral("/api/v1/proxyurl"),
                                    kRemoteTimeoutMs);
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
        reply->deleteLater();
        if (generation != m_proxyUrlGeneration) return;
        m_proxyUrlInFlight = false;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        // Any HTTP answer is final until the remote settings change; only a
        // network failure is worth another try on the next refresh().
        if (status > 0) m_proxyUrlSettled = true;
        if (status != 200) {
            // Not a cloud, or not reachable right now: the remote URL is used
            // for the Main UI.
            qDebug() << "[ConnectionManager] no proxy URL from remote, HTTP" << status;
            return;
        }
        const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        const QString url = normalizeUrl(obj.value(QStringLiteral("url")).toString());
        if (url.isEmpty() || url == m_remoteProxyUrl) return;
        m_remoteProxyUrl = url;
        qDebug() << "[ConnectionManager] Main UI via" << url;
        if (usingRemote()) emit activeChanged();
    });
}

void ConnectionManager::publishRemoteAuth()
{
    // Requests QML makes without its own header (Image, charts) get the
    // remote credentials injected, but only for exactly this origin.
    if (remoteConfigured() && !m_remote.user.isEmpty() && !m_remote.password.isEmpty()) {
        RemoteAuth::set(originOf(m_remote.url), basicAuth(m_remote.user, m_remote.password));
    } else {
        RemoteAuth::clear();
    }
}

// ── Choosing the connection ─────────────────────────────────────────

void ConnectionManager::refresh()
{
    m_quietRetry = false;
    m_retryAttempt = 0;
    m_retryLocal = false;
    probe();
}

void ConnectionManager::onNetworkSettled()
{
    m_quietRetry = false;
    m_retryAttempt = 0;
    m_retryLocal = true;
    renewNetworkAccess();
    probe();
}

void ConnectionManager::renewNetworkAccess()
{
    abortProbes();
    if (m_proxyUrlInFlight) {
        ++m_proxyUrlGeneration;     // its answer is ignored, fetched again
        m_proxyUrlInFlight = false;
    }
    // Replies are children of the old QNAM and go with it.
    m_nam->deleteLater();
    m_nam = new QNetworkAccessManager(this);
}

void ConnectionManager::setForeground(bool foreground)
{
    if (m_foreground == foreground) return;
    m_foreground = foreground;
    updateLocalRecheck();
}

void ConnectionManager::updateLocalRecheck()
{
    const bool wanted = m_foreground && remoteConfigured() && !m_local.url.isEmpty()
            && m_type == QLatin1String("remote");
    if (wanted && !m_localRecheck.isActive()) {
        m_localRecheck.start();
    } else if (!wanted) {
        m_localRecheck.stop();
    }
}

void ConnectionManager::probe()
{
    abortProbes();
    // Retries after a failed round get a fresh QNAM too (see m_nam).
    if (m_retryAttempt > 0 && remoteConfigured()) renewNetworkAccess();

    // The proxy URL could not be fetched earlier (e.g. offline at start).
    if (remoteConfigured() && !m_proxyUrlSettled && !m_proxyUrlInFlight) {
        fetchProxyUrl();
    }

    if (!remoteConfigured()) {
        // Old behaviour: always local, nothing probed.
        setChecking(false);
        setActive(QStringLiteral("local"));
        return;
    }

    qDebug() << "[ConnectionManager] probing local" << m_local.url
             << "and remote" << m_remote.url;
    if (!m_quietRetry) setChecking(true);
    m_quietRetry = false;

    m_localDone = m_local.url.isEmpty();
    m_localOk = false;
    m_remoteDone = false;
    m_remoteOk = false;

    if (!m_localDone) {
        m_localReply = startGet(m_nam, m_local, QStringLiteral("/rest/"), kLocalTimeoutMs);
    }
    m_remoteReply = startGet(m_nam, m_remote, QStringLiteral("/rest/"), kRemoteTimeoutMs);

    const int generation = m_generation;
    if (m_localReply) {
        QNetworkReply *reply = m_localReply;
        connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
            onProbeFinished(reply, true, generation);
        });
    }
    QNetworkReply *reply = m_remoteReply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
        onProbeFinished(reply, false, generation);
    });

    // No local URL at all → decide as soon as remote answers.
    if (m_localDone) {
        decide();
    }
}

QNetworkReply *ConnectionManager::startGet(QNetworkAccessManager *nam, const Endpoint &ep,
                                           const QString &path, int timeoutMs)
{
    // Qt 5.6 keeps a QNAM "not accessible" after its network session went
    // away (Wi-Fi lost) and then fails every request right away.
    nam->setNetworkAccessible(QNetworkAccessManager::Accessible);

    QNetworkRequest request(QUrl(ep.url + path));
    request.setRawHeader("Accept", "application/json");
    if (!ep.user.isEmpty() && !ep.password.isEmpty()) {
        request.setRawHeader("Authorization", basicAuth(ep.user, ep.password));
    }
    // Probes must see the real answer, not a cached one.
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::AlwaysNetwork);
    QNetworkReply *reply = nam->get(request);
    // QNetworkRequest::setTransferTimeout() only exists from Qt 5.15 on.
    QTimer::singleShot(timeoutMs, reply, [reply]() {
        if (reply->isRunning()) reply->abort();
    });
    return reply;
}

void ConnectionManager::onProbeFinished(QNetworkReply *reply, bool isLocal, int generation)
{
    reply->deleteLater();
    if (isLocal && reply == m_localReply) m_localReply = nullptr;
    if (!isLocal && reply == m_remoteReply) m_remoteReply = nullptr;
    if (generation != m_generation) return;   // superseded by a newer round

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const ProbeResult result = classifyRestProbe(status,
                                                 reply->error() != QNetworkReply::NoError,
                                                 reply->readAll(), isLocal);
    qDebug() << "[ConnectionManager]" << (isLocal ? "local" : "remote")
             << "probe:" << resultName(result) << "HTTP" << status;

    if (isLocal) {
        m_localDone = true;
        // A local server that asks for credentials is still the local
        // server -- using it surfaces the "not authorized" error where the
        // user expects it, instead of silently going through the cloud.
        m_localOk = (result == Ok || result == Unauthorized);
    } else {
        m_remoteDone = true;
        m_remoteOk = (result == Ok);
    }
    decide();
}

void ConnectionManager::decide()
{
    if (m_localDone && m_localOk) {
        m_graceTimer.stop();
        abortProbes();
        setChecking(false);
        setActive(QStringLiteral("local"));
        return;
    }
    if (m_remoteDone && m_remoteOk) {
        if (m_localDone) {
            m_graceTimer.stop();
            setChecking(false);
            setActive(QStringLiteral("remote"));
            // Local preferred: try it again shortly after a network change.
            if (m_retryLocal) scheduleRetry(false);
        } else if (m_type == QLatin1String("remote")) {
            // Already on remote: nothing to wait for, local may still win.
            setChecking(false);
        } else if (!m_graceTimer.isActive()) {
            // Remote was faster -- give local a moment, it is preferred.
            m_graceTimer.start();
        }
        return;
    }
    if (m_localDone && m_remoteDone) {
        // Keep the current connection (and "checking") while retrying.
        if (scheduleRetry(true)) return;
        setChecking(false);
        setActive(QStringLiteral("none"));
    }
}

bool ConnectionManager::scheduleRetry(bool allFailed)
{
    const int delay = m_retriesEnabled ? retryDelayMs(m_retryAttempt, allFailed) : -1;
    if (delay < 0) return false;
    ++m_retryAttempt;
    m_quietRetry = !allFailed;
    qDebug() << "[ConnectionManager] retry" << m_retryAttempt << "in" << delay << "ms";
    m_retryTimer.start(delay);
    return true;
}

int ConnectionManager::retryDelayMs(int attempt, bool allFailed)
{
    const int count = allFailed ? kRetryCount : kLocalRetryCount;
    if (attempt < 0 || attempt >= count) return -1;
    return kRetryDelaysMs[attempt];
}

void ConnectionManager::onGraceExpired()
{
    // Use remote now, but let the local probe run to its timeout: if local
    // still answers, decide() switches back to it.
    if (m_localOk || !m_remoteOk) return;
    setChecking(false);
    setActive(QStringLiteral("remote"));
}

void ConnectionManager::abortProbes()
{
    m_graceTimer.stop();
    m_retryTimer.stop();
    // Ends the current round: answers that still arrive (abort() emits
    // finished() right away) carry the old generation and are ignored.
    ++m_generation;
    QNetworkReply *local = m_localReply;
    QNetworkReply *remote = m_remoteReply;
    m_localReply = nullptr;
    m_remoteReply = nullptr;
    if (local && local->isRunning()) local->abort();
    if (remote && remote->isRunning()) remote->abort();
}

void ConnectionManager::setActive(const QString &type)
{
    if (type != QLatin1String("none")) m_lastReachable = type;
    const bool useRemote = type == QLatin1String("remote")
            || (type == QLatin1String("none") && m_lastReachable == QLatin1String("remote")
                && remoteConfigured());
    const Endpoint &ep = useRemote ? m_remote : m_local;
    if (type == m_type && ep.url == m_activeUrl && ep.user == m_activeUser
            && ep.password == m_activePassword) {
        return;
    }
    const bool typeChanged = type != m_type;
    m_type = type;
    m_activeUrl = ep.url;
    m_activeUser = ep.user;
    m_activePassword = ep.password;
    if (typeChanged) {
        qDebug() << "[ConnectionManager] active connection:" << m_type << m_activeUrl;
    }
    updateLocalRecheck();
    emit activeChanged();
}

void ConnectionManager::setChecking(bool checking)
{
    if (m_checking == checking) return;
    m_checking = checking;
    emit checkingChanged();
}

void ConnectionManager::onNetworkChanged()
{
    // configurationChanged() also fires for Wi-Fi scan results. Only a change
    // of the *active* connections (or of the online state) is worth a probe.
    QStringList active;
    const auto configs = m_netConfig.allConfigurations(QNetworkConfiguration::Active);
    for (const QNetworkConfiguration &cfg : configs) {
        active << cfg.identifier();
    }
    active.sort();
    const QString fingerprint = (m_netConfig.isOnline() ? QStringLiteral("on|") : QStringLiteral("off|"))
            + active.join(QLatin1Char(','));
    if (fingerprint == m_netFingerprint) return;
    m_netFingerprint = fingerprint;

    if (!remoteConfigured()) return;
    // Show "checking" right away instead of a stale state.
    setChecking(true);
    m_networkDebounce.start();
}

// ── Connection test (settings page) ─────────────────────────────────

void ConnectionManager::testConnections(const QString &localUrl, const QString &localUser,
                                        const QString &localPassword,
                                        const QString &remoteUrl, const QString &remoteUser,
                                        const QString &remotePassword)
{
    const int generation = ++m_testGeneration;
    m_testLocalResult = QStringLiteral("skipped");
    m_testRemoteResult = QStringLiteral("skipped");
    m_testPending = 0;

    Endpoint local { normalizeUrl(localUrl), localUser, localPassword };
    Endpoint remote { normalizeUrl(remoteUrl), remoteUser, remotePassword };

    if (!local.url.isEmpty()) {
        ++m_testPending;
        QNetworkReply *reply = startGet(&m_testNam, local, QStringLiteral("/rest/"),
                                        kRemoteTimeoutMs);
        connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
            reply->deleteLater();
            if (generation != m_testGeneration) return;
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            m_testLocalResult = resultName(classifyRestProbe(
                    status, reply->error() != QNetworkReply::NoError, reply->readAll(), true));
            --m_testPending;
            finishTestIfDone();
        });
    }

    if (!remote.url.isEmpty()) {
        // Two requests in parallel: /rest/ says whether openHAB is reachable
        // through it, /api/v1/settings/notifications whether it is an
        // openHAB Cloud at all (404 there = some other reverse proxy).
        ++m_testPending;
        struct RemoteTest { int restStatus = -1; bool restError = false; QByteArray restBody;
                            int cloudStatus = -1; };
        QSharedPointer<RemoteTest> state(new RemoteTest);

        auto evaluate = [this, state, generation]() {
            if (generation != m_testGeneration) return;
            if (state->restStatus < 0 || state->cloudStatus < 0) return;   // one still running
            ProbeResult rest = classifyRestProbe(state->restStatus, state->restError,
                                                 state->restBody, false);
            const bool isCloud = state->cloudStatus == 200;
            ProbeResult result = rest;
            if (rest == Ok && !isCloud) {
                result = OkNoCloud;
            } else if (rest == Offline && !isCloud) {
                result = HttpError;
            }
            m_testRemoteResult = resultName(result);
            --m_testPending;
            finishTestIfDone();
        };

        QNetworkReply *restReply = startGet(&m_testNam, remote, QStringLiteral("/rest/"),
                                            kRemoteTimeoutMs);
        connect(restReply, &QNetworkReply::finished, this, [restReply, state, evaluate]() {
            restReply->deleteLater();
            state->restStatus = restReply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            state->restError = restReply->error() != QNetworkReply::NoError;
            state->restBody = restReply->readAll();
            evaluate();
        });

        QNetworkReply *cloudReply = startGet(&m_testNam, remote,
                                             QStringLiteral("/api/v1/settings/notifications"),
                                             kRemoteTimeoutMs);
        connect(cloudReply, &QNetworkReply::finished, this, [cloudReply, state, evaluate]() {
            cloudReply->deleteLater();
            state->cloudStatus = cloudReply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            evaluate();
        });
    }

    if (!m_testing) {
        m_testing = true;
        emit testingChanged();
    }
    finishTestIfDone();
}

void ConnectionManager::finishTestIfDone()
{
    if (m_testPending > 0) return;
    if (m_testing) {
        m_testing = false;
        emit testingChanged();
    }
    emit testFinished(m_testLocalResult, m_testRemoteResult);
}

// ── Pure helpers ────────────────────────────────────────────────────

QString ConnectionManager::normalizeUrl(const QString &url)
{
    // Mirrors Settings.qml normalizeUrl(): fix "http:/host", drop trailing slashes.
    QString result = url.trimmed();
    static const QRegularExpression singleSlash(QStringLiteral("^(https?):/([^/])"));
    result.replace(singleSlash, QStringLiteral("\\1://\\2"));
    while (result.endsWith(QLatin1Char('/'))) {
        result.chop(1);
    }
    return result;
}

QString ConnectionManager::originOf(const QString &url)
{
    const QUrl u(url);
    if (!u.isValid() || u.host().isEmpty()) return QString();
    const QString scheme = u.scheme().toLower();
    const int port = u.port(scheme == QLatin1String("https") ? 443 : 80);
    return scheme + QStringLiteral("://") + u.host().toLower() + QLatin1Char(':')
            + QString::number(port);
}

QByteArray ConnectionManager::basicAuth(const QString &user, const QString &password)
{
    return "Basic " + (user + QLatin1Char(':') + password).toUtf8().toBase64();
}

ConnectionManager::ProbeResult ConnectionManager::classifyRestProbe(int httpStatus, bool networkError,
                                                                    const QByteArray &body,
                                                                    bool isLocal)
{
    if (httpStatus <= 0) {
        return networkError ? Network : HttpError;
    }
    if (httpStatus == 401 || httpStatus == 403) {
        return Unauthorized;
    }
    if (httpStatus >= 200 && httpStatus < 300) {
        // A captive portal or an unrelated web server on the same address
        // also answers 200 -- only openHAB's API root has these fields.
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            if (obj.contains(QStringLiteral("links")) || obj.contains(QStringLiteral("version"))) {
                return Ok;
            }
        }
        return NotOpenHab;
    }
    if (httpStatus >= 500 && !isLocal) {
        // The cloud answers 5xx when the openHAB server behind it is not
        // connected.
        return Offline;
    }
    return HttpError;
}

QString ConnectionManager::resultName(ProbeResult result)
{
    switch (result) {
    case Ok:           return QStringLiteral("ok");
    case OkNoCloud:    return QStringLiteral("okNoCloud");
    case Network:      return QStringLiteral("network");
    case Unauthorized: return QStringLiteral("unauthorized");
    case Offline:      return QStringLiteral("offline");
    case NotOpenHab:   return QStringLiteral("notOpenHab");
    case HttpError:    return QStringLiteral("http");
    }
    return QStringLiteral("http");
}
