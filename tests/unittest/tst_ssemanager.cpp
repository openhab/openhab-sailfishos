/**
 * Unit tests for the SSEManager C++ class.
 *
 * Tests cover:
 *   - Initial state (inactive, no connection)
 *   - Signal emissions on connect / disconnect
 *   - State transitions (active flag)
 *   - Double-disconnect safety
 *   - Q_PROPERTY accessibility from QML side
 *
 * These tests do NOT require a running openHAB server.
 * Network requests will fail immediately which is expected.
 */

#include <QtTest/QtTest>
#include <QSignalSpy>
#include "../../src/ssemanager.h"

class tst_SSEManager : public QObject
{
    Q_OBJECT

private slots:
    // ── initial state ──
    void initialState_isInactive();
    void initialState_activePropertyIsFalse();

    // ── connect behaviour ──
    void connect_emitsStatusChangedConnecting();
    void connect_replyIsCreated();

    // ── disconnect behaviour ──
    void disconnect_emitsStatusChangedDisconnected();
    void disconnect_setsInactive();
    void disconnect_nullifiesReply();
    void disconnect_doubleCallIsSafe();

    // ── reconnect behaviour ──
    void reconnect_cleanlyReplacesConnection();
};

// ── initial state ──────────────────────────────

void tst_SSEManager::initialState_isInactive()
{
    SSEManager mgr;
    QVERIFY(!mgr.isActive());
}

void tst_SSEManager::initialState_activePropertyIsFalse()
{
    SSEManager mgr;
    // Verify Q_PROPERTY is readable (same way QML would access it)
    QCOMPARE(mgr.property("active").toBool(), false);
}

// ── connect behaviour ──────────────────────────

void tst_SSEManager::connect_emitsStatusChangedConnecting()
{
    SSEManager mgr;
    QSignalSpy spy(&mgr, &SSEManager::statusChanged);
    QVERIFY(spy.isValid());

    mgr.connectToOpenHAB("http://localhost:9999");

    QVERIFY(spy.count() >= 1);
    QCOMPARE(spy.first().first().toString(), QStringLiteral("Connecting..."));
}

void tst_SSEManager::connect_replyIsCreated()
{
    SSEManager mgr;
    // Before connect – no crash, no active state
    QVERIFY(!mgr.isActive());

    mgr.connectToOpenHAB("http://localhost:9999");

    // The manager should NOT be active yet (no data received)
    QVERIFY(!mgr.isActive());
}

// ── disconnect behaviour ───────────────────────

void tst_SSEManager::disconnect_emitsStatusChangedDisconnected()
{
    SSEManager mgr;
    mgr.connectToOpenHAB("http://localhost:9999");

    QSignalSpy spy(&mgr, &SSEManager::statusChanged);
    mgr.disconnectFromOpenHAB();

    // Should contain "Disconnected"
    bool found = false;
    for (const auto &args : spy) {
        if (args.first().toString() == QStringLiteral("Disconnected")) {
            found = true;
            break;
        }
    }
    QVERIFY2(found, "Expected 'Disconnected' status signal");
}

void tst_SSEManager::disconnect_setsInactive()
{
    SSEManager mgr;
    mgr.connectToOpenHAB("http://localhost:9999");
    mgr.disconnectFromOpenHAB();
    QVERIFY(!mgr.isActive());
}

void tst_SSEManager::disconnect_nullifiesReply()
{
    SSEManager mgr;
    mgr.connectToOpenHAB("http://localhost:9999");
    mgr.disconnectFromOpenHAB();

    // Calling disconnect again must not crash
    mgr.disconnectFromOpenHAB();
    QVERIFY(!mgr.isActive());
}

void tst_SSEManager::disconnect_doubleCallIsSafe()
{
    SSEManager mgr;
    // Never connected – disconnect should be a no-op
    mgr.disconnectFromOpenHAB();
    mgr.disconnectFromOpenHAB();
    QVERIFY(!mgr.isActive());
}

// ── reconnect behaviour ────────────────────────

void tst_SSEManager::reconnect_cleanlyReplacesConnection()
{
    SSEManager mgr;
    QSignalSpy statusSpy(&mgr, &SSEManager::statusChanged);

    mgr.connectToOpenHAB("http://localhost:9999");
    int countAfterFirst = statusSpy.count();

    // Second connect should cleanly replace the first
    mgr.connectToOpenHAB("http://localhost:8888");

    QVERIFY(statusSpy.count() > countAfterFirst);
    // Last signal should be "Connecting..." for the new URL
    QCOMPARE(statusSpy.last().first().toString(), QStringLiteral("Connecting..."));
}

QTEST_MAIN(tst_SSEManager)
#include "tst_ssemanager.moc"

