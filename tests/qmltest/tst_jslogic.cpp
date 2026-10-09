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

    // ── PatternFormatter: formatNumber – SI unit conversion ──
    void pf_formatNumber_siWattToKiloWatt();
    void pf_formatNumber_siKiloWattToWatt();
    void pf_formatNumber_siCrossPrefix();
    void pf_formatNumber_siMilliToBase();

    // ── PatternFormatter: formatNumber – exponent notation ──
    void pf_formatNumber_exponentNotation();
    void pf_formatNumber_exponentWithUnit();

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

    // ── NfcUri: building ──
    void nfc_buildShortItemUri();
    void nfc_buildLongItemUri();
    void nfc_buildOmitsEmptyOptionals();
    void nfc_buildEncodesSpecialCharacters();
    void nfc_buildRejectsMissingFields();
    void nfc_buildSitemapUri();
    void nfc_buildSitemapUriAddsLeadingSlash();

    // ── NfcUri: parsing item tags ──
    void nfc_parseShortItemUri();
    void nfc_parseLongItemUri();
    void nfc_parseDeprecatedAliases();
    void nfc_parseDecodesPercentEncoding();
    void nfc_parseIgnoresUnknownParameters();

    // ── NfcUri: rejection paths ──
    void nfc_parseRejectsForeignScheme();
    void nfc_parseRejectsEmpty();
    void nfc_parseRejectsDeviceIdTag();
    void nfc_parseRejectsMissingItem();
    void nfc_parseRejectsMissingCommand();
    void nfc_parseSurvivesMalformedEscape();

    // ── NfcUri: sitemap tags ──
    void nfc_parseSitemapRoot();
    void nfc_parseSitemapSubPage();
    void nfc_isSubPagePath();
    void nfc_rootSitemapOf();

    // ── NfcUri: round trips ──
    void nfc_roundTripItem();
    void nfc_roundTripSitemap();

    // ── OpenHabApi: pure helpers ──
    void api_baseTypeOf();
    void api_classifyError();
    void api_commandsPreferCommandOptions();
    void api_commandsFallBackToMappings();
    void api_commandsFallBackToStaticTable();
    void api_commandsEmptyMeansFreeText();
    void api_collectSitemapItems();
    void api_collectSitemapItemsSkipsReadOnly();
    void api_filterCommandableItems();
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

    // ── Load NfcUri.js (openhab:// tag URIs) ──
    loadScript(QStringLiteral("../../qml/base/utilities/NfcUri.js"));

    // ── Load OpenHabApi.js ──
    // Only its pure helpers are exercised here; the XHR based functions need
    // a server and the Qt object, neither of which exists in QJSEngine.
    loadScript(QStringLiteral("../../qml/base/utilities/OpenHabApi.js"));

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
//  PatternFormatter – formatNumber: SI unit conversion
// ════════════════════════════════════════════════

// "1000 W" with pattern "%.1f kW"  → W÷1000 = 1.0 kW
void tst_JsLogic::pf_formatNumber_siWattToKiloWatt() {
    QCOMPARE(engine.evaluate("formatState('%.1f kW', '1000 W')").toString(), QStringLiteral("1.0 kW"));
}

// "1 kW" with pattern "%.0f W"  → kW×1000 = 1000 W
void tst_JsLogic::pf_formatNumber_siKiloWattToWatt() {
    QCOMPARE(engine.evaluate("formatState('%.0f W', '1 kW')").toString(), QStringLiteral("1000 W"));
}

// "374.0 kWh" with pattern "%.2f MWh"  → kWh×1e3÷1e6 = 0.37 MWh
void tst_JsLogic::pf_formatNumber_siCrossPrefix() {
    QCOMPARE(engine.evaluate("formatState('%.2f MWh', '374.0 kWh')").toString(), QStringLiteral("0.37 MWh"));
}

// "500 mW" with pattern "%.2f W"  → mW×1e-3 = 0.50 W
void tst_JsLogic::pf_formatNumber_siMilliToBase() {
    QCOMPARE(engine.evaluate("formatState('%.2f W', '500 mW')").toString(), QStringLiteral("0.50 W"));
}

// ════════════════════════════════════════════════
//  PatternFormatter – formatNumber: exponent notation
// ════════════════════════════════════════════════

// Pure exponent input "1e3" → parseFloat gives 1000
void tst_JsLogic::pf_formatNumber_exponentNotation() {
    QCOMPARE(engine.evaluate("formatState('%.0f', '1e3')").toString(), QStringLiteral("1000"));
}

// Exponent WITH unit: "1.5e3 W" + pattern "%.1f kW"  → 1500 W ÷ 1000 = 1.5 kW
void tst_JsLogic::pf_formatNumber_exponentWithUnit() {
    QCOMPARE(engine.evaluate("formatState('%.1f kW', '1.5e3 W')").toString(), QStringLiteral("1.5 kW"));
}

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

// ════════════════════════════════════════════════
//  NfcUri – building openhab:// tag URIs
//
//  The exact wire format is dictated by the openHAB Android app. These tests
//  are what stops a refactoring from silently producing tags Android cannot
//  read.
// ════════════════════════════════════════════════

void tst_JsLogic::nfc_buildShortItemUri() {
    QCOMPARE(engine.evaluate("buildShortItemUri('Light', 'ON')").toString(),
             QStringLiteral("openhab://?i=Light&s=ON"));
}

void tst_JsLogic::nfc_buildLongItemUri() {
    QCOMPARE(engine.evaluate("buildItemUri('Light', 'ON', 'Kitchen', 'On')").toString(),
             QStringLiteral("openhab://?i=Light&s=ON&l=Kitchen&m=On"));
}

void tst_JsLogic::nfc_buildOmitsEmptyOptionals() {
    // Empty optionals must vanish entirely, not appear as "&l=".
    QCOMPARE(engine.evaluate("buildItemUri('Light', 'ON', '', '')").toString(),
             QStringLiteral("openhab://?i=Light&s=ON"));
    QCOMPARE(engine.evaluate("buildItemUri('Light', 'ON', 'Kitchen', '')").toString(),
             QStringLiteral("openhab://?i=Light&s=ON&l=Kitchen"));
}

void tst_JsLogic::nfc_buildEncodesSpecialCharacters() {
    // Labels carry spaces and umlauts, HSB commands carry commas.
    QCOMPARE(engine.evaluate("buildItemUri('Light', 'ON', 'Küche Decke', '')").toString(),
             QStringLiteral("openhab://?i=Light&s=ON&l=K%C3%BCche%20Decke"));
    QCOMPARE(engine.evaluate("buildItemUri('RGB', '0,100,50', '', '')").toString(),
             QStringLiteral("openhab://?i=RGB&s=0%2C100%2C50"));
}

void tst_JsLogic::nfc_buildRejectsMissingFields() {
    QCOMPARE(engine.evaluate("buildItemUri('', 'ON', '', '')").toString(), QStringLiteral(""));
    QCOMPARE(engine.evaluate("buildItemUri('Light', '', '', '')").toString(), QStringLiteral(""));
}

void tst_JsLogic::nfc_buildSitemapUri() {
    QCOMPARE(engine.evaluate("buildSitemapUri('/demo/0100')").toString(),
             QStringLiteral("openhab:///demo/0100"));
}

void tst_JsLogic::nfc_buildSitemapUriAddsLeadingSlash() {
    QCOMPARE(engine.evaluate("buildSitemapUri('demo')").toString(),
             QStringLiteral("openhab:///demo"));
}

// ════════════════════════════════════════════════
//  NfcUri – parsing item tags
// ════════════════════════════════════════════════

void tst_JsLogic::nfc_parseShortItemUri() {
    engine.evaluate("var r = parse('openhab://?i=Light&s=ON')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.kind").toString(), QStringLiteral("item"));
    QCOMPARE(engine.evaluate("r.item").toString(), QStringLiteral("Light"));
    QCOMPARE(engine.evaluate("r.command").toString(), QStringLiteral("ON"));
}

void tst_JsLogic::nfc_parseLongItemUri() {
    engine.evaluate("var r = parse('openhab://?i=Light&s=ON&l=Kitchen&m=On')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.label").toString(), QStringLiteral("Kitchen"));
    QCOMPARE(engine.evaluate("r.mappedState").toString(), QStringLiteral("On"));
}

void tst_JsLogic::nfc_parseDeprecatedAliases() {
    // Written by older Android versions; still read, never written.
    engine.evaluate("var r = parse('openhab://?item=Light&command=OFF')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.item").toString(), QStringLiteral("Light"));
    QCOMPARE(engine.evaluate("r.command").toString(), QStringLiteral("OFF"));
}

void tst_JsLogic::nfc_parseDecodesPercentEncoding() {
    engine.evaluate("var r = parse('openhab://?i=RGB&s=0%2C100%2C50&l=K%C3%BCche%20Decke')");
    QCOMPARE(engine.evaluate("r.command").toString(), QStringLiteral("0,100,50"));
    QCOMPARE(engine.evaluate("r.label").toString(), QString::fromUtf8("Küche Decke"));
}

void tst_JsLogic::nfc_parseIgnoresUnknownParameters() {
    engine.evaluate("var r = parse('openhab://?i=Light&s=ON&zzz=1')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.item").toString(), QStringLiteral("Light"));
}

// ════════════════════════════════════════════════
//  NfcUri – rejection paths
// ════════════════════════════════════════════════

void tst_JsLogic::nfc_parseRejectsForeignScheme() {
    engine.evaluate("var r = parse('https://example.org/')");
    QVERIFY(!engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.reason").toString(), QStringLiteral("notOpenhab"));
}

void tst_JsLogic::nfc_parseRejectsEmpty() {
    engine.evaluate("var r = parse('')");
    QVERIFY(!engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.reason").toString(), QStringLiteral("empty"));
}

void tst_JsLogic::nfc_parseRejectsDeviceIdTag() {
    // Android's device-id mode: the state is a placeholder that must never be
    // sent to the server verbatim.
    engine.evaluate("var r = parse('openhab://?i=Phone&s=UNSUPPORTED&d=true')");
    QVERIFY(!engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.reason").toString(), QStringLiteral("deviceId"));
}

void tst_JsLogic::nfc_parseRejectsMissingItem() {
    engine.evaluate("var r = parse('openhab://?s=ON')");
    QVERIFY(!engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.reason").toString(), QStringLiteral("missingItem"));
}

void tst_JsLogic::nfc_parseRejectsMissingCommand() {
    engine.evaluate("var r = parse('openhab://?i=Light')");
    QVERIFY(!engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.reason").toString(), QStringLiteral("missingCommand"));
}

void tst_JsLogic::nfc_parseSurvivesMalformedEscape() {
    // A broken escape must not throw out of the read path.
    engine.evaluate("var r = parse('openhab://?i=Light&s=1%ZZ')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.command").toString(), QStringLiteral("1%ZZ"));
}

// ════════════════════════════════════════════════
//  NfcUri – sitemap tags
// ════════════════════════════════════════════════

void tst_JsLogic::nfc_parseSitemapRoot() {
    engine.evaluate("var r = parse('openhab:///demo')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.kind").toString(), QStringLiteral("sitemap"));
    QCOMPARE(engine.evaluate("r.path").toString(), QStringLiteral("/demo"));
    QCOMPARE(engine.evaluate("r.rootSitemap").toString(), QStringLiteral("demo"));
}

void tst_JsLogic::nfc_parseSitemapSubPage() {
    engine.evaluate("var r = parse('openhab:///demo/0100')");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.path").toString(), QStringLiteral("/demo/0100"));
    // Only the root may be persisted as lastVisitedPage.
    QCOMPARE(engine.evaluate("r.rootSitemap").toString(), QStringLiteral("demo"));
}

void tst_JsLogic::nfc_isSubPagePath() {
    QVERIFY(engine.evaluate("isSubPagePath('/demo/0100')").toBool());
    QVERIFY(!engine.evaluate("isSubPagePath('/demo')").toBool());
    QVERIFY(!engine.evaluate("isSubPagePath('')").toBool());
}

void tst_JsLogic::nfc_rootSitemapOf() {
    QCOMPARE(engine.evaluate("rootSitemapOf('/demo/0100')").toString(), QStringLiteral("demo"));
    QCOMPARE(engine.evaluate("rootSitemapOf('demo')").toString(), QStringLiteral("demo"));
    QCOMPARE(engine.evaluate("rootSitemapOf('')").toString(), QStringLiteral(""));
}

// ════════════════════════════════════════════════
//  NfcUri – round trips
// ════════════════════════════════════════════════

void tst_JsLogic::nfc_roundTripItem() {
    engine.evaluate("var u = buildItemUri('Licht_WZ', 'ON', 'Wohnzimmer Decke', 'Ein');"
                    "var r = parse(u);");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.item").toString(), QStringLiteral("Licht_WZ"));
    QCOMPARE(engine.evaluate("r.command").toString(), QStringLiteral("ON"));
    QCOMPARE(engine.evaluate("r.label").toString(), QStringLiteral("Wohnzimmer Decke"));
    QCOMPARE(engine.evaluate("r.mappedState").toString(), QStringLiteral("Ein"));
}

void tst_JsLogic::nfc_roundTripSitemap() {
    engine.evaluate("var u = buildSitemapUri('/demo/0100');"
                    "var r = parse(u);");
    QVERIFY(engine.evaluate("r.valid").toBool());
    QCOMPARE(engine.evaluate("r.path").toString(), QStringLiteral("/demo/0100"));
}

// ════════════════════════════════════════════════
//  OpenHabApi – pure helpers
// ════════════════════════════════════════════════

void tst_JsLogic::api_baseTypeOf() {
    QCOMPARE(engine.evaluate("baseTypeOf('Switch')").toString(),              QStringLiteral("Switch"));
    QCOMPARE(engine.evaluate("baseTypeOf('Number:Temperature')").toString(),  QStringLiteral("Number"));
    QCOMPARE(engine.evaluate("baseTypeOf('Group:Switch')").toString(),        QStringLiteral("Switch"));
    QCOMPARE(engine.evaluate("baseTypeOf('Group:Number:Temperature')").toString(), QStringLiteral("Number"));
    QCOMPARE(engine.evaluate("baseTypeOf('')").toString(),                    QStringLiteral(""));
}

void tst_JsLogic::api_classifyError() {
    // Telling these apart is the whole point here: a switched off server
    // must not be reported as "this item does not exist".
    QCOMPARE(engine.evaluate("classifyError({status: 0}).kind").toString(),   QStringLiteral("network"));
    QCOMPARE(engine.evaluate("classifyError({status: 404}).kind").toString(), QStringLiteral("notFound"));
    QCOMPARE(engine.evaluate("classifyError({status: 401}).kind").toString(), QStringLiteral("unauthorized"));
    QCOMPARE(engine.evaluate("classifyError({status: 403}).kind").toString(), QStringLiteral("unauthorized"));
    QCOMPARE(engine.evaluate("classifyError({status: 503}).kind").toString(), QStringLiteral("server"));
    QCOMPARE(engine.evaluate("classifyError({status: 418}).kind").toString(), QStringLiteral("http"));
}

void tst_JsLogic::api_commandsPreferCommandOptions() {
    engine.evaluate(
        "var item = { type:'String', commandDescription: { commandOptions: ["
        "  { command:'A', label:'Alpha' }, { command:'B' } ] } };"
        "var r = commandsForItem(item, [{command:'M', label:'Mapped'}], {String:['X']});");
    QCOMPARE(engine.evaluate("r.length").toInt(), 2);
    QCOMPARE(engine.evaluate("r[0].command").toString(), QStringLiteral("A"));
    QCOMPARE(engine.evaluate("r[0].label").toString(),   QStringLiteral("Alpha"));
    // Missing label falls back to the command itself.
    QCOMPARE(engine.evaluate("r[1].label").toString(),   QStringLiteral("B"));
}

void tst_JsLogic::api_commandsFallBackToMappings() {
    engine.evaluate(
        "var item = { type:'Switch' };"
        "var r = commandsForItem(item, [{command:'ON', label:'Ein'}], {Switch:['ON','OFF']});");
    QCOMPARE(engine.evaluate("r.length").toInt(), 1);
    QCOMPARE(engine.evaluate("r[0].label").toString(), QStringLiteral("Ein"));
}

void tst_JsLogic::api_commandsFallBackToStaticTable() {
    engine.evaluate(
        "var item = { type:'Switch' };"
        "var r = commandsForItem(item, [], {Switch:['ON','OFF']});");
    QCOMPARE(engine.evaluate("r.length").toInt(), 2);
    QCOMPARE(engine.evaluate("r[1].command").toString(), QStringLiteral("OFF"));
}

void tst_JsLogic::api_commandsEmptyMeansFreeText() {
    // Number has no fixed command list -- the page must offer free text.
    engine.evaluate("var r = commandsForItem({type:'Number'}, [], {Number:[]});");
    QCOMPARE(engine.evaluate("r.length").toInt(), 0);
    // Unknown type behaves the same rather than throwing.
    engine.evaluate("var r2 = commandsForItem({type:'Whatever'}, [], {Switch:['ON']});");
    QCOMPARE(engine.evaluate("r2.length").toInt(), 0);
}

void tst_JsLogic::api_collectSitemapItems() {
    engine.evaluate(
        "var sitemap = { homepage: { widgets: ["
        "  { label:'Light [ON]', item:{ name:'Light', type:'Switch' } },"
        "  { type:'Frame', widgets: ["
        "      { label:'Blind', item:{ name:'Blind', type:'Rollershutter' } },"
        "      { label:'Light again', item:{ name:'Light', type:'Switch' } } ] } ] } };"
        "var r = collectSitemapItems(sitemap, []);");
    // Depth first, duplicates dropped.
    QCOMPARE(engine.evaluate("r.length").toInt(), 2);
    QCOMPARE(engine.evaluate("r[0].name").toString(), QStringLiteral("Light"));
    // The "[ON]" state part of a sitemap label is not part of the item name.
    QCOMPARE(engine.evaluate("r[0].label").toString(), QStringLiteral("Light"));
    QCOMPARE(engine.evaluate("r[1].name").toString(), QStringLiteral("Blind"));
}

void tst_JsLogic::api_collectSitemapItemsSkipsReadOnly() {
    engine.evaluate(
        "var sitemap = { widgets: ["
        "  { label:'Door', item:{ name:'Door', type:'Contact' } },"
        "  { label:'Light', item:{ name:'Light', type:'Switch' } } ] };"
        "var r = collectSitemapItems(sitemap, ['Contact']);");
    QCOMPARE(engine.evaluate("r.length").toInt(), 1);
    QCOMPARE(engine.evaluate("r[0].name").toString(), QStringLiteral("Light"));
}

void tst_JsLogic::api_filterCommandableItems() {
    engine.evaluate(
        "var items = ["
        "  { name:'Door',  type:'Contact' },"
        "  { name:'Light', type:'Switch', label:'Kitchen' },"
        "  { name:'Temp',  type:'Number:Temperature' } ];"
        "var r = filterCommandableItems(items, ['Contact']);");
    QCOMPARE(engine.evaluate("r.length").toInt(), 2);
    QCOMPARE(engine.evaluate("r[0].label").toString(), QStringLiteral("Kitchen"));
    // No label -> the name stands in.
    QCOMPARE(engine.evaluate("r[1].label").toString(), QStringLiteral("Temp"));
}

QTEST_MAIN(tst_JsLogic)
#include "tst_jslogic.moc"

