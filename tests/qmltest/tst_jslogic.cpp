/**
 * C++ unit tests for all JavaScript / QML logic.
 *
 * Uses QJSEngine to evaluate the production JS files directly – no Qt Quick
 * scene graph or OpenGL context required.  This makes the tests run reliably
 * in headless / offscreen environments (sfdk build, CI).
 *
 * Covered modules:
 *   - PatternFormatter.js  (formatState, formatNumber, formatDateTime, zeroPad)
 *   - normalizeUrl()       (from Settings.qml – re-implemented for isolation)
 *   - SseEvents.js         (handleSSEMessage with a MockModel)
 */

#include <QtTest/QtTest>
#include <QJSEngine>
#include <QFile>
#include <QTextStream>

class tst_JsLogic : public QObject
{
    Q_OBJECT

private:
    QJSEngine engine;

    /** Load a file relative to SRCDIR and return its contents. */
    QString loadFile(const QString &relativePath) {
        QString path = QStringLiteral(SRCDIR) + QStringLiteral("/") + relativePath;
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    qWarning() << "Cannot open:" << path;
                    return QString();
                }
        QTextStream stream(&f);
        return stream.readAll();
    }

    /** Load a .pragma library JS file into the global scope. */
    void loadScript(const QString &relativePath) {
        QString code = loadFile(relativePath);
        // .pragma library is a QML-only directive – strip it for QJSEngine
        code.replace(QStringLiteral(".pragma library"), QStringLiteral("// .pragma library"));
        QJSValue result = engine.evaluate(code, relativePath);
        QVERIFY2(!result.isError(),
                 qPrintable(QString("%1: %2").arg(relativePath, result.toString())));
    }

private slots:
    void initTestCase();

    // ── PatternFormatter: zeroPad ──
    void pf_zeroPad_singleDigit();
    void pf_zeroPad_alreadyWide();
    void pf_zeroPad_widthThree();
    void pf_zeroPad_zero();

    // ── PatternFormatter: formatState edge cases ──
    void pf_formatState_emptyPattern();
    void pf_formatState_NULL();
    void pf_formatState_UNDEF();
    void pf_formatState_empty();

    // ── PatternFormatter: formatNumber ──
    void pf_formatNumber_integer();
    void pf_formatNumber_integerRoundsUp();
    void pf_formatNumber_float2dec();
    void pf_formatNumber_float1dec();
    void pf_formatNumber_float0dec();
    void pf_formatNumber_float3dec();
    void pf_formatNumber_string();
    void pf_formatNumber_unitWatt();
    void pf_formatNumber_unitKwh();
    void pf_formatNumber_literalPercent();
    void pf_formatNumber_withText();
    void pf_formatNumber_negative();

    // ── PatternFormatter: formatDateTime ──
    void pf_formatDateTime_dayMonthYear();
    void pf_formatDateTime_hourMinute();
    void pf_formatDateTime_isoDate();
    void pf_formatDateTime_timeHHMMSS();
    void pf_formatDateTime_timeHHMM();
    void pf_formatDateTime_invalidDate();
    void pf_formatDateTime_combined();
    void pf_formatDateTime_literalPercent();

    // ── normalizeUrl ──
    void url_normalUnchanged();
    void url_ipWithPort();
    void url_trailingSlash();
    void url_multipleTrailingSlashes();
    void url_singleSlashHttp();
    void url_singleSlashHttps();
    void url_combined();
    void url_empty();
    void url_withPath();

    // ── SseEvents: handleSSEMessage ──
    void sse_updatesModel();
    void sse_ignoresNonStateChanged();
    void sse_unknownItemUnchanged();
    void sse_malformedJson();
    void sse_emptyMessage();
    void sse_unchangedState();
    void sse_multipleRows();
};

// ════════════════════════════════════════════════
//  Setup
// ════════════════════════════════════════════════

void tst_JsLogic::initTestCase()
{
    // Provide a dummy console object (used by the production JS files)
    engine.evaluate(QStringLiteral(
        "var console = {"
        "  log:   function() {},"
        "  warn:  function() {},"
        "  error: function() {}"
        "};"));

    // ── Load PatternFormatter.js (functions become global) ──
    loadScript(QStringLiteral("../../qml/base/utilities/PatternFormatter.js"));

    // ── Load normalizeUrl (mirrors Settings.qml) ──
    engine.evaluate(QStringLiteral(
        "function normalizeUrl(url) {"
        "  var p = /^(https?):[\\/]([^\\/])/;"
        "  if (p.test(url)) url = url.replace(p, '$1://$2');"
        "  while (url.length > 0 && url.charAt(url.length - 1) === '/') {"
        "    url = url.substring(0, url.length - 1);"
        "  }"
        "  return url;"
        "}"));

    // ── Load SseEvents.js ──
    loadScript(QStringLiteral("../../qml/base/utilities/SseEvents.js"));

    // ── MockModel (replaces QML ListModel for SSE tests) ──
    engine.evaluate(QStringLiteral(
        "function MockModel() { this._items = []; this.count = 0; }"
        "MockModel.prototype.append = function(item) {"
        "  this._items.push(JSON.parse(JSON.stringify(item)));"
        "  this.count = this._items.length;"
        "};"
        "MockModel.prototype.get = function(i) { return this._items[i]; };"
        "MockModel.prototype.setProperty = function(i, prop, val) {"
        "  this._items[i][prop] = (typeof val === 'object') ? JSON.parse(JSON.stringify(val)) : val;"
        "};"
        "MockModel.prototype.clear = function() { this._items = []; this.count = 0; };"));
}

// ════════════════════════════════════════════════
//  PatternFormatter – zeroPad
// ════════════════════════════════════════════════

void tst_JsLogic::pf_zeroPad_singleDigit()  { QCOMPARE(engine.evaluate("zeroPad(5, 2)").toString(),  QStringLiteral("05")); }
void tst_JsLogic::pf_zeroPad_alreadyWide()  { QCOMPARE(engine.evaluate("zeroPad(12, 2)").toString(), QStringLiteral("12")); }
void tst_JsLogic::pf_zeroPad_widthThree()   { QCOMPARE(engine.evaluate("zeroPad(7, 3)").toString(),  QStringLiteral("007")); }
void tst_JsLogic::pf_zeroPad_zero()          { QCOMPARE(engine.evaluate("zeroPad(0, 2)").toString(),  QStringLiteral("00")); }

// ════════════════════════════════════════════════
//  PatternFormatter – formatState edge cases
// ════════════════════════════════════════════════

void tst_JsLogic::pf_formatState_emptyPattern() { QCOMPARE(engine.evaluate("formatState('', '23')").toString(),      QStringLiteral("23")); }
void tst_JsLogic::pf_formatState_NULL()          { QCOMPARE(engine.evaluate("formatState('%d', 'NULL')").toString(),  QStringLiteral("NULL")); }
void tst_JsLogic::pf_formatState_UNDEF()         { QCOMPARE(engine.evaluate("formatState('%d', 'UNDEF')").toString(), QStringLiteral("UNDEF")); }
void tst_JsLogic::pf_formatState_empty()          { QCOMPARE(engine.evaluate("formatState('%d', '')").toString(),     QStringLiteral("")); }

// ════════════════════════════════════════════════
//  PatternFormatter – formatNumber
// ════════════════════════════════════════════════

void tst_JsLogic::pf_formatNumber_integer()        { QCOMPARE(engine.evaluate("formatState('%d', '23')").toString(),              QStringLiteral("23")); }
void tst_JsLogic::pf_formatNumber_integerRoundsUp() { QCOMPARE(engine.evaluate("formatState('%d', '23.7')").toString(),           QStringLiteral("24")); }
void tst_JsLogic::pf_formatNumber_float2dec()       { QCOMPARE(engine.evaluate("formatState('%.2f', '23.456')").toString(),       QStringLiteral("23.46")); }
void tst_JsLogic::pf_formatNumber_float1dec()       { QCOMPARE(engine.evaluate("formatState('%.1f', '11.1')").toString(),         QStringLiteral("11.1")); }
void tst_JsLogic::pf_formatNumber_float0dec()       { QCOMPARE(engine.evaluate("formatState('%.0f', '23.7')").toString(),         QStringLiteral("24")); }
void tst_JsLogic::pf_formatNumber_float3dec()       { QCOMPARE(engine.evaluate("formatState('%.3f', '1.1')").toString(),          QStringLiteral("1.100")); }
void tst_JsLogic::pf_formatNumber_string()          { QCOMPARE(engine.evaluate("formatState('%s', 'Hello')").toString(),           QStringLiteral("Hello")); }
void tst_JsLogic::pf_formatNumber_unitWatt()        { QCOMPARE(engine.evaluate("formatState('%.1f %unit%', '11.1 W')").toString(), QStringLiteral("11.1 W")); }
void tst_JsLogic::pf_formatNumber_unitKwh()         { QCOMPARE(engine.evaluate("formatState('%.1f %unit%', '374.0 kWh')").toString(), QStringLiteral("374.0 kWh")); }
void tst_JsLogic::pf_formatNumber_literalPercent()  { QCOMPARE(engine.evaluate("formatState('%d %%', '50')").toString(),           QStringLiteral("50 %")); }
void tst_JsLogic::pf_formatNumber_withText()        { QCOMPARE(engine.evaluate("formatState('Power: %.1f %unit%', '11.1 W')").toString(), QStringLiteral("Power: 11.1 W")); }
void tst_JsLogic::pf_formatNumber_negative()        { QCOMPARE(engine.evaluate("formatState('%d', '-5.2')").toString(),           QStringLiteral("-5")); }

// ════════════════════════════════════════════════
//  PatternFormatter – formatDateTime
// ════════════════════════════════════════════════

void tst_JsLogic::pf_formatDateTime_dayMonthYear() {
    QString r = engine.evaluate("formatState('%1$td.%1$tm.%1$tY', '2026-03-10T13:17:38.000+0100')").toString();
    QVERIFY2(QRegExp("^\\d{2}\\.\\d{2}\\.\\d{4}$").exactMatch(r), qPrintable("Expected DD.MM.YYYY, got: " + r));
}
void tst_JsLogic::pf_formatDateTime_hourMinute() {
    QString r = engine.evaluate("formatState('%1$tH:%1$tM', '2026-03-10T13:17:38.000+0100')").toString();
    QVERIFY2(QRegExp("^\\d{2}:\\d{2}$").exactMatch(r), qPrintable("Expected HH:MM, got: " + r));
}
void tst_JsLogic::pf_formatDateTime_isoDate() {
    QString r = engine.evaluate("formatState('%1$tF', '2026-06-15T10:30:00.000+0200')").toString();
    QVERIFY2(QRegExp("^\\d{4}-\\d{2}-\\d{2}$").exactMatch(r), qPrintable("Expected YYYY-MM-DD, got: " + r));
}
void tst_JsLogic::pf_formatDateTime_timeHHMMSS() {
    QString r = engine.evaluate("formatState('%1$tT', '2026-06-15T10:30:45.000+0200')").toString();
    QVERIFY2(QRegExp("^\\d{2}:\\d{2}:\\d{2}$").exactMatch(r), qPrintable("Expected HH:MM:SS, got: " + r));
}
void tst_JsLogic::pf_formatDateTime_timeHHMM() {
    QString r = engine.evaluate("formatState('%1$tR', '2026-06-15T10:30:00.000+0200')").toString();
    QVERIFY2(QRegExp("^\\d{2}:\\d{2}$").exactMatch(r), qPrintable("Expected HH:MM, got: " + r));
}
void tst_JsLogic::pf_formatDateTime_invalidDate() {
    QCOMPARE(engine.evaluate("formatState('%1$td.%1$tm.%1$tY', 'not-a-date')").toString(), QStringLiteral("not-a-date"));
}
void tst_JsLogic::pf_formatDateTime_combined() {
    QString r = engine.evaluate("formatState('%1$td.%1$tm.%1$tY %1$tH:%1$tM Uhr', '2026-03-10T13:17:38.000+0100')").toString();
    QVERIFY2(r.contains(QStringLiteral("Uhr")), qPrintable("Expected 'Uhr' in: " + r));
    QVERIFY2(QRegExp("^\\d{2}\\.\\d{2}\\.\\d{4} \\d{2}:\\d{2} Uhr$").exactMatch(r), qPrintable("Unexpected format: " + r));
}
void tst_JsLogic::pf_formatDateTime_literalPercent() {
    QString r = engine.evaluate("formatState('%1$tH:%1$tM %%', '2026-06-15T10:30:00.000+0200')").toString();
    QVERIFY2(QRegExp("^\\d{2}:\\d{2} %$").exactMatch(r), qPrintable("Expected 'HH:MM %', got: " + r));
}

// ════════════════════════════════════════════════
//  normalizeUrl
// ════════════════════════════════════════════════

void tst_JsLogic::url_normalUnchanged()       { QCOMPARE(engine.evaluate("normalizeUrl('https://demo.openhab.org')").toString(),     QStringLiteral("https://demo.openhab.org")); }
void tst_JsLogic::url_ipWithPort()             { QCOMPARE(engine.evaluate("normalizeUrl('http://192.168.1.100:8080')").toString(),   QStringLiteral("http://192.168.1.100:8080")); }
void tst_JsLogic::url_trailingSlash()          { QCOMPARE(engine.evaluate("normalizeUrl('https://demo.openhab.org/')").toString(),   QStringLiteral("https://demo.openhab.org")); }
void tst_JsLogic::url_multipleTrailingSlashes() { QCOMPARE(engine.evaluate("normalizeUrl('https://demo.openhab.org///')").toString(), QStringLiteral("https://demo.openhab.org")); }
void tst_JsLogic::url_singleSlashHttp()        { QCOMPARE(engine.evaluate("normalizeUrl('http:/example.com')").toString(),           QStringLiteral("http://example.com")); }
void tst_JsLogic::url_singleSlashHttps()       { QCOMPARE(engine.evaluate("normalizeUrl('https:/myserver.local')").toString(),       QStringLiteral("https://myserver.local")); }
void tst_JsLogic::url_combined()               { QCOMPARE(engine.evaluate("normalizeUrl('http:/example.com/')").toString(),          QStringLiteral("http://example.com")); }
void tst_JsLogic::url_empty()                  { QCOMPARE(engine.evaluate("normalizeUrl('')").toString(),                             QStringLiteral("")); }
void tst_JsLogic::url_withPath()               { QCOMPARE(engine.evaluate("normalizeUrl('https://example.com/openhab/')").toString(), QStringLiteral("https://example.com/openhab")); }

// ════════════════════════════════════════════════
//  SseEvents – handleSSEMessage
// ════════════════════════════════════════════════

void tst_JsLogic::sse_updatesModel() {
    engine.evaluate(
        "var _m1 = new MockModel();"
        "_m1.append({ itemName:'Temp', itemState:'20.0', itemData:{ state:'20.0' } });"
        "rebindModel(_m1);"
        "handleSSEMessage(JSON.stringify({"
        "  type:'ItemStateChangedEvent',"
        "  topic:'openhab/items/Temp/statechanged',"
        "  payload:JSON.stringify({ value:'22.5' })"
        "}));");
    QCOMPARE(engine.evaluate("_m1.get(0).itemState").toString(), QStringLiteral("22.5"));
    engine.evaluate("rebindModel(null)");
}

void tst_JsLogic::sse_ignoresNonStateChanged() {
    engine.evaluate(
        "var _m2 = new MockModel();"
        "_m2.append({ itemName:'Temp', itemState:'20.0', itemData:{ state:'20.0' } });"
        "rebindModel(_m2);"
        "handleSSEMessage(JSON.stringify({"
        "  type:'ItemStateEvent',"
        "  topic:'openhab/items/Temp/state',"
        "  payload:JSON.stringify({ value:'22.5' })"
        "}));");
    QCOMPARE(engine.evaluate("_m2.get(0).itemState").toString(), QStringLiteral("20.0"));
    engine.evaluate("rebindModel(null)");
}

void tst_JsLogic::sse_unknownItemUnchanged() {
    engine.evaluate(
        "var _m3 = new MockModel();"
        "_m3.append({ itemName:'Temp', itemState:'20.0', itemData:{ state:'20.0' } });"
        "rebindModel(_m3);"
        "handleSSEMessage(JSON.stringify({"
        "  type:'ItemStateChangedEvent',"
        "  topic:'openhab/items/Unknown/statechanged',"
        "  payload:JSON.stringify({ value:'99' })"
        "}));");
    QCOMPARE(engine.evaluate("_m3.get(0).itemState").toString(), QStringLiteral("20.0"));
    engine.evaluate("rebindModel(null)");
}

void tst_JsLogic::sse_malformedJson() {
    engine.evaluate(
        "var _m4 = new MockModel();"
        "_m4.append({ itemName:'Temp', itemState:'20.0', itemData:{ state:'20.0' } });"
        "rebindModel(_m4);"
        "handleSSEMessage('this is not json {{{');");
    QCOMPARE(engine.evaluate("_m4.get(0).itemState").toString(), QStringLiteral("20.0"));
    engine.evaluate("rebindModel(null)");
}

void tst_JsLogic::sse_emptyMessage() {
    engine.evaluate(
        "rebindModel(new MockModel());"
        "handleSSEMessage('');"
        "handleSSEMessage(null);"
        "handleSSEMessage(undefined);"
        "rebindModel(null);");
    // No crash = pass
}

void tst_JsLogic::sse_unchangedState() {
    engine.evaluate(
        "var _m5 = new MockModel();"
        "_m5.append({ itemName:'Temp', itemState:'20.0', itemData:{ state:'20.0' } });"
        "rebindModel(_m5);"
        "handleSSEMessage(JSON.stringify({"
        "  type:'ItemStateChangedEvent',"
        "  topic:'openhab/items/Temp/statechanged',"
        "  payload:JSON.stringify({ value:'20.0' })"
        "}));");
    QCOMPARE(engine.evaluate("_m5.get(0).itemState").toString(), QStringLiteral("20.0"));
    engine.evaluate("rebindModel(null)");
}

void tst_JsLogic::sse_multipleRows() {
    engine.evaluate(
        "var _m6 = new MockModel();"
        "_m6.append({ itemName:'Blind', itemState:'50', itemData:{ state:'50' } });"
        "_m6.append({ itemName:'Blind', itemState:'50', itemData:{ state:'50' } });"
        "rebindModel(_m6);"
        "handleSSEMessage(JSON.stringify({"
        "  type:'ItemStateChangedEvent',"
        "  topic:'openhab/items/Blind/statechanged',"
        "  payload:JSON.stringify({ value:'75' })"
        "}));");
    QCOMPARE(engine.evaluate("_m6.get(0).itemState").toString(), QStringLiteral("75"));
    QCOMPARE(engine.evaluate("_m6.get(1).itemState").toString(), QStringLiteral("75"));
    engine.evaluate("rebindModel(null)");
}

QTEST_MAIN(tst_JsLogic)
#include "tst_jslogic.moc"

