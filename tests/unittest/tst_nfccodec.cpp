/**
 * Unit tests for NfcCodec -- the NDEF / Type 2 TLV byte layer.
 *
 * These tests are the compatibility guarantee towards the openHAB Android app
 * -- the golden vectors below fix the NDEF message bytes, so a change in the encoder cannot silently break tags
 * written by Android.
 *
 * The "factory image" used throughout is the real content of a brand new
 * NTAG213, captured on a Fairphone 4 running Sailfish OS 5.0.0.72
 * (nfc-tag-dump-20260907-135055.log):
 *
 *     01 03 a0 0c 34 03 00 fe 00 00 ... (144 bytes total)
 *      ^^^^^^^^^^^^^ Lock Control TLV -- must survive a write
 */

#include <QtTest/QtTest>
#include "nfccodec.h"

class tst_NfcCodec : public QObject
{
    Q_OBJECT

private:
    /** Data area of a factory fresh NTAG213, exactly as read from hardware. */
    static QByteArray factoryImage()
    {
        QByteArray data;
        static const char header[] = "\x01\x03\xa0\x0c\x34\x03\x00\xfe";
        data.append(header, 8);
        data.append(QByteArray(144 - 8, '\0'));
        return data;
    }

    /** A tag whose leading TLVs were already destroyed by ndef-write. */
    static QByteArray clobberedImage()
    {
        QByteArray data;
        static const char header[] = "\x03\x00\xfe";
        data.append(header, 3);
        data.append(QByteArray(144 - 3, '\0'));
        return data;
    }

private slots:
    // ── TLV chain walking ──
    void tlvOffset_factoryTagSkipsLockControl();
    void tlvOffset_clobberedTagStartsAtZero();
    void tlvOffset_emptyData();
    void tlvOffset_truncatedChain();
    void message_factoryTagIsEmpty();

    // ── capacity ──
    void capacity_factoryTag();
    void capacity_clobberedTag();
    void capacity_tooSmallForAnything();

    // ── URI record encoding (golden vectors) ──
    void golden_shortItemUri();
    void golden_longItemUri();
    void golden_sitemapUri();
    void golden_specialCharactersInLabel();
    void buildUriMessage_empty();

    // ── record decoding ──
    void uriFromPayload_noAbbreviation();
    void uriFromPayload_httpsAbbreviation();
    void uriFromPayload_empty();
    void uriFromMessage_rejectsNonUriRecord();
    void uriFromMessage_rejectsTruncated();
    void uriFromMessage_longRecordForm();

    // ── writing an image ──
    void image_preservesLockControlTlv();
    void image_keepsDataAreaLength();
    void image_zeroFillsTail();
    void image_readBackYieldsSameMessage();
    void image_rejectsOversizedMessage();
    void image_acceptsExactlyFittingMessage();
    void image_overwritesLongerPreviousContent();

    // ── write diff ──
    void diff_onlyChangedPrefix();
    void diff_identicalImageWritesNothing();

    // ── full round trip ──
    void roundTrip_writeThenRead();
};

// ---------------------------------------------------------------------------
// TLV chain walking
// ---------------------------------------------------------------------------

void tst_NfcCodec::tlvOffset_factoryTagSkipsLockControl()
{
    // The Lock Control TLV is 01 03 a0 0c 34 -> five bytes, so the NDEF TLV
    // sits at offset 5. Anything that assumes offset 0 breaks here.
    QCOMPARE(NfcCodec::ndefTlvOffset(factoryImage()), 5);
}

void tst_NfcCodec::tlvOffset_clobberedTagStartsAtZero()
{
    QCOMPARE(NfcCodec::ndefTlvOffset(clobberedImage()), 0);
}

void tst_NfcCodec::tlvOffset_emptyData()
{
    QCOMPARE(NfcCodec::ndefTlvOffset(QByteArray()), 0);
}

void tst_NfcCodec::tlvOffset_truncatedChain()
{
    // A Lock Control TLV whose length byte is missing must not read past the end.
    QByteArray data;
    data.append(char(0x01));
    QCOMPARE(NfcCodec::ndefTlvOffset(data), 1);
}

void tst_NfcCodec::message_factoryTagIsEmpty()
{
    // 03 00 is a valid but empty NDEF message TLV. A brand new tag is not
    // "unformatted", it genuinely carries an empty message.
    QVERIFY(NfcCodec::ndefMessageFromData(factoryImage()).isEmpty());
}

// ---------------------------------------------------------------------------
// Capacity
// ---------------------------------------------------------------------------

void tst_NfcCodec::capacity_factoryTag()
{
    // 144 - 5 (lock TLV) - 3 (0x03 + length byte + terminator) = 136
    QCOMPARE(NfcCodec::capacity(factoryImage()), 136);
}

void tst_NfcCodec::capacity_clobberedTag()
{
    // Without the lock TLV there are five bytes more to play with.
    QCOMPARE(NfcCodec::capacity(clobberedImage()), 141);
}

void tst_NfcCodec::capacity_tooSmallForAnything()
{
    QCOMPARE(NfcCodec::capacity(QByteArray(2, '\0')), 0);
}

// ---------------------------------------------------------------------------
// Golden vectors -- these fix binary compatibility with the Android app
// ---------------------------------------------------------------------------

void tst_NfcCodec::golden_shortItemUri()
{
    const QByteArray message =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=Light&s=ON"));

    static const quint8 expected[] = {
        0xd1, 0x01, 0x18, 0x55, 0x00,
        'o', 'p', 'e', 'n', 'h', 'a', 'b', ':', '/', '/', '?',
        'i', '=', 'L', 'i', 'g', 'h', 't', '&', 's', '=', 'O', 'N'
    };
    QCOMPARE(message,
             QByteArray(reinterpret_cast<const char *>(expected), sizeof(expected)));
}

void tst_NfcCodec::golden_longItemUri()
{
    const QString uri =
            QStringLiteral("openhab://?i=Light&s=ON&l=Kitchen%20light&m=On");
    const QByteArray message = NfcCodec::buildUriMessage(uri);

    QCOMPARE(quint8(message.at(0)), quint8(0xd1));   // MB|ME|SR|TNF=1
    QCOMPARE(quint8(message.at(1)), quint8(0x01));   // type length
    QCOMPARE(quint8(message.at(2)), quint8(uri.toUtf8().size() + 1));
    QCOMPARE(message.at(3), 'U');
    QCOMPARE(quint8(message.at(4)), quint8(0x00));   // no abbreviation
    QCOMPARE(message.mid(5), uri.toUtf8());
}

void tst_NfcCodec::golden_sitemapUri()
{
    const QString uri = QStringLiteral("openhab:///demo/0100");
    const QByteArray message = NfcCodec::buildUriMessage(uri);

    QCOMPARE(quint8(message.at(0)), quint8(0xd1));
    QCOMPARE(message.at(3), 'U');
    QCOMPARE(NfcCodec::uriFromMessage(message), uri);
}

void tst_NfcCodec::golden_specialCharactersInLabel()
{
    // Percent encoding happens one layer up in NfcUri.js; the codec must pass
    // the bytes through untouched and count them in UTF-8, not in QChars.
    const QString uri = QStringLiteral("openhab://?i=Light&s=ON&l=Gr%C3%BCn");
    const QByteArray message = NfcCodec::buildUriMessage(uri);
    QCOMPARE(quint8(message.at(2)), quint8(uri.toUtf8().size() + 1));
    QCOMPARE(NfcCodec::uriFromMessage(message), uri);
}

void tst_NfcCodec::buildUriMessage_empty()
{
    QVERIFY(NfcCodec::buildUriMessage(QString()).isEmpty());
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

void tst_NfcCodec::uriFromPayload_noAbbreviation()
{
    QByteArray payload;
    payload.append(char(0x00));
    payload.append("openhab://?i=X&s=ON");
    QCOMPARE(NfcCodec::uriFromPayload(payload),
             QStringLiteral("openhab://?i=X&s=ON"));
}

void tst_NfcCodec::uriFromPayload_httpsAbbreviation()
{
    // Not an openHAB tag, but the decoder must still resolve it correctly
    // rather than silently dropping the prefix.
    QByteArray payload;
    payload.append(char(0x04));
    payload.append("example.org");
    QCOMPARE(NfcCodec::uriFromPayload(payload),
             QStringLiteral("https://example.org"));
}

void tst_NfcCodec::uriFromPayload_empty()
{
    QVERIFY(NfcCodec::uriFromPayload(QByteArray()).isEmpty());
}

void tst_NfcCodec::uriFromMessage_rejectsNonUriRecord()
{
    // Well-known record of type "T" (text), not "U".
    QByteArray message;
    message.append(char(0xd1));
    message.append(char(0x01));
    message.append(char(0x03));
    message.append('T');
    message.append("abc");
    QVERIFY(NfcCodec::uriFromMessage(message).isEmpty());
}

void tst_NfcCodec::uriFromMessage_rejectsTruncated()
{
    QByteArray message;
    message.append(char(0xd1));
    message.append(char(0x01));
    message.append(char(0x40));      // claims 64 bytes of payload
    message.append('U');
    message.append(char(0x00));
    message.append("short");
    QVERIFY(NfcCodec::uriFromMessage(message).isEmpty());
}

void tst_NfcCodec::uriFromMessage_longRecordForm()
{
    const QString uri = QStringLiteral("openhab://?i=X&s=") + QString(300, QChar('a'));
    const QByteArray message = NfcCodec::buildUriMessage(uri);
    QCOMPARE(quint8(message.at(0)), quint8(0xc1));   // no SR bit
    QCOMPARE(NfcCodec::uriFromMessage(message), uri);
}

// ---------------------------------------------------------------------------
// Building the replacement image
// ---------------------------------------------------------------------------

void tst_NfcCodec::image_preservesLockControlTlv()
{
    const QByteArray current = factoryImage();
    const QByteArray message =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=Light&s=ON"));
    const QByteArray image = NfcCodec::buildTagImage(current, message);

    QVERIFY(!image.isEmpty());
    // This is the whole point of deviating from ndef-write.c.
    QCOMPARE(image.left(5), current.left(5));
    QCOMPARE(quint8(image.at(5)), quint8(0x03));
    QCOMPARE(quint8(image.at(6)), quint8(message.size()));
}

void tst_NfcCodec::image_keepsDataAreaLength()
{
    const QByteArray current = factoryImage();
    const QByteArray image = NfcCodec::buildTagImage(
                current, NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=A&s=ON")));
    QCOMPARE(image.size(), current.size());
}

void tst_NfcCodec::image_zeroFillsTail()
{
    const QByteArray current = factoryImage();
    const QByteArray message =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=A&s=ON"));
    const QByteArray image = NfcCodec::buildTagImage(current, message);

    const int used = 5 + 2 + message.size() + 1;
    QCOMPARE(image.mid(used), QByteArray(current.size() - used, '\0'));
}

void tst_NfcCodec::image_readBackYieldsSameMessage()
{
    const QByteArray message =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=Light&s=OFF"));
    const QByteArray image = NfcCodec::buildTagImage(factoryImage(), message);
    QCOMPARE(NfcCodec::ndefMessageFromData(image), message);
}

void tst_NfcCodec::image_rejectsOversizedMessage()
{
    const QByteArray current = factoryImage();
    // One byte more than capacity() allows.
    const QByteArray message(NfcCodec::capacity(current) + 1, 'x');
    QVERIFY(NfcCodec::buildTagImage(current, message).isEmpty());
}

void tst_NfcCodec::image_acceptsExactlyFittingMessage()
{
    const QByteArray current = factoryImage();
    const QByteArray message(NfcCodec::capacity(current), 'x');
    const QByteArray image = NfcCodec::buildTagImage(current, message);
    QCOMPARE(image.size(), current.size());
}

void tst_NfcCodec::image_overwritesLongerPreviousContent()
{
    // Write a long URI first, then a short one: no remnant of the long one
    // may survive, otherwise a reader could pick up stale bytes.
    QByteArray current = NfcCodec::buildTagImage(
                factoryImage(),
                NfcCodec::buildUriMessage(QStringLiteral(
                    "openhab://?i=VeryLongItemName&s=ON&l=A%20rather%20long%20label")));
    QVERIFY(!current.isEmpty());

    const QByteArray shortMessage =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=A&s=ON"));
    const QByteArray image = NfcCodec::buildTagImage(current, shortMessage);

    QCOMPARE(NfcCodec::ndefMessageFromData(image), shortMessage);
    const int used = 5 + 2 + shortMessage.size() + 1;
    QCOMPARE(image.mid(used), QByteArray(image.size() - used, '\0'));
}

// ---------------------------------------------------------------------------
// Write diff
// ---------------------------------------------------------------------------

void tst_NfcCodec::diff_onlyChangedPrefix()
{
    const QByteArray current = factoryImage();
    const QByteArray message =
            NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=Light&s=ON"));
    const QByteArray image = NfcCodec::buildTagImage(current, message);

    // Everything behind the terminator is zero in both images, so the write
    // stops right after it.
    QCOMPARE(NfcCodec::changedPrefixLength(image, current),
             5 + 2 + message.size() + 1);
}

void tst_NfcCodec::diff_identicalImageWritesNothing()
{
    const QByteArray image = NfcCodec::buildTagImage(
                factoryImage(),
                NfcCodec::buildUriMessage(QStringLiteral("openhab://?i=A&s=ON")));
    QCOMPARE(NfcCodec::changedPrefixLength(image, image), 0);
}

// ---------------------------------------------------------------------------
// Round trip
// ---------------------------------------------------------------------------

void tst_NfcCodec::roundTrip_writeThenRead()
{
    const QString uri =
            QStringLiteral("openhab://?i=Licht_Wohnzimmer&s=ON&l=Wohnzimmerlicht&m=Ein");
    const QByteArray image =
            NfcCodec::buildTagImage(factoryImage(), NfcCodec::buildUriMessage(uri));
    QVERIFY(!image.isEmpty());
    QCOMPARE(NfcCodec::uriFromMessage(NfcCodec::ndefMessageFromData(image)), uri);
}

QTEST_APPLESS_MAIN(tst_NfcCodec)
#include "tst_nfccodec.moc"
