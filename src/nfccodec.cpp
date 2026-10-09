#include "nfccodec.h"

namespace {

/**
 * URI abbreviation codes from the NFC Forum URI Record Type Definition.
 * Index 0 means "no abbreviation, the URI follows verbatim" -- which is what
 * openhab:// URIs use, both here and in the Android app.
 */
const char * const kUriPrefixes[] = {
    "",                            // 0x00
    "http://www.",                 // 0x01
    "https://www.",                // 0x02
    "http://",                     // 0x03
    "https://",                    // 0x04
    "tel:",                        // 0x05
    "mailto:",                     // 0x06
    "ftp://anonymous:anonymous@",  // 0x07
    "ftp://ftp.",                  // 0x08
    "ftps://",                     // 0x09
    "sftp://",                     // 0x0a
    "smb://",                      // 0x0b
    "nfs://",                      // 0x0c
    "ftp://",                      // 0x0d
    "dav://",                      // 0x0e
    "news:",                       // 0x0f
    "telnet://",                   // 0x10
    "imap:",                       // 0x11
    "rtsp://",                     // 0x12
    "urn:",                        // 0x13
    "pop:",                        // 0x14
    "sip:",                        // 0x15
    "sips:",                       // 0x16
    "tftp:",                       // 0x17
    "btspp://",                    // 0x18
    "btl2cap://",                  // 0x19
    "btgoep://",                   // 0x1a
    "tcpobex://",                  // 0x1b
    "irdaobex://",                 // 0x1c
    "file://",                     // 0x1d
    "urn:epc:id:",                 // 0x1e
    "urn:epc:tag:",                // 0x1f
    "urn:epc:pat:",                // 0x20
    "urn:epc:raw:",                // 0x21
    "urn:epc:",                    // 0x22
    "urn:nfc:"                     // 0x23
};
const int kUriPrefixCount = int(sizeof(kUriPrefixes) / sizeof(kUriPrefixes[0]));

inline quint8 byteAt(const QByteArray &data, int index)
{
    return static_cast<quint8>(data.at(index));
}

/**
 * Read the length field of the TLV starting at `offset`.
 * Returns the size of the type+length header, or -1 when the TLV is truncated.
 * `valueLength` receives the length of the value part.
 */
int tlvHeaderSize(const QByteArray &data, int offset, int *valueLength)
{
    *valueLength = 0;
    if (offset + 1 >= data.size()) {
        return -1;
    }
    if (byteAt(data, offset + 1) == 0xff) {
        // Three consecutive bytes format: 0xff followed by a 16 bit length.
        if (offset + 3 >= data.size()) {
            return -1;
        }
        *valueLength = (byteAt(data, offset + 2) << 8) | byteAt(data, offset + 3);
        return 4;
    }
    *valueLength = byteAt(data, offset + 1);
    return 2;
}

} // namespace

// ---------------------------------------------------------------------------
// NDEF record level
// ---------------------------------------------------------------------------

QByteArray NfcCodec::buildUriMessage(const QString &uri)
{
    if (uri.isEmpty()) {
        return QByteArray();
    }

    QByteArray payload;
    payload.append(char(0x00));            // no abbreviation
    payload.append(uri.toUtf8());

    QByteArray message;
    if (payload.size() < 0x100) {
        // Short record: MB | ME | SR | TNF=1
        message.append(char(0xd1));
        message.append(char(0x01));                       // type length
        message.append(char(payload.size() & 0xff));      // payload length
    } else {
        // Long record: MB | ME | TNF=1, four byte payload length
        message.append(char(0xc1));
        message.append(char(0x01));
        message.append(char((payload.size() >> 24) & 0xff));
        message.append(char((payload.size() >> 16) & 0xff));
        message.append(char((payload.size() >> 8) & 0xff));
        message.append(char(payload.size() & 0xff));
    }
    message.append('U');                   // well-known type "U" (URI)
    message.append(payload);
    return message;
}

QString NfcCodec::uriFromPayload(const QByteArray &payload)
{
    if (payload.isEmpty()) {
        return QString();
    }
    const quint8 code = byteAt(payload, 0);
    QString prefix;
    if (code < kUriPrefixCount) {
        prefix = QString::fromLatin1(kUriPrefixes[code]);
    }
    return prefix + QString::fromUtf8(payload.mid(1));
}

QString NfcCodec::uriFromMessage(const QByteArray &message)
{
    if (message.size() < 3) {
        return QString();
    }

    const quint8 header = byteAt(message, 0);
    const bool shortRecord = (header & 0x10) != 0;
    const quint8 tnf = header & 0x07;
    const bool hasIdLength = (header & 0x08) != 0;
    if (tnf != TnfWellKnown) {
        return QString();
    }

    int offset = 1;
    const quint8 typeLength = byteAt(message, offset++);

    int payloadLength = 0;
    if (shortRecord) {
        if (offset >= message.size()) {
            return QString();
        }
        payloadLength = byteAt(message, offset++);
    } else {
        if (offset + 3 >= message.size()) {
            return QString();
        }
        payloadLength = (byteAt(message, offset) << 24)
                      | (byteAt(message, offset + 1) << 16)
                      | (byteAt(message, offset + 2) << 8)
                      | byteAt(message, offset + 3);
        offset += 4;
    }

    int idLength = 0;
    if (hasIdLength) {
        if (offset >= message.size()) {
            return QString();
        }
        idLength = byteAt(message, offset++);
    }

    if (offset + typeLength > message.size()) {
        return QString();
    }
    const QByteArray type = message.mid(offset, typeLength);
    offset += typeLength + idLength;

    if (type != QByteArray("U")) {
        return QString();
    }
    if (payloadLength <= 0 || offset + payloadLength > message.size()) {
        return QString();
    }
    return uriFromPayload(message.mid(offset, payloadLength));
}

// ---------------------------------------------------------------------------
// Type 2 TLV level
// ---------------------------------------------------------------------------

int NfcCodec::ndefTlvOffset(const QByteArray &data)
{
    int offset = 0;
    while (offset < data.size()) {
        const quint8 type = byteAt(data, offset);
        if (type == TlvNdefMessage || type == TlvTerminator) {
            return offset;
        }
        if (type == TlvNull) {
            offset += 1;
            continue;
        }
        if (type != TlvLockControl && type != TlvMemoryControl
                && type != TlvProprietary) {
            // Unknown type -- the chain is not something we understand, so
            // treat this position as the place to write and let the caller
            // decide. Overwriting from here is what ndef-write would do too.
            return offset;
        }
        int valueLength = 0;
        const int header = tlvHeaderSize(data, offset, &valueLength);
        if (header < 0) {
            return data.size();
        }
        offset += header + valueLength;
    }
    return data.size();
}

QByteArray NfcCodec::ndefMessageFromData(const QByteArray &data)
{
    const int offset = ndefTlvOffset(data);
    if (offset >= data.size() || byteAt(data, offset) != TlvNdefMessage) {
        return QByteArray();
    }
    int valueLength = 0;
    const int header = tlvHeaderSize(data, offset, &valueLength);
    if (header < 0 || valueLength <= 0) {
        return QByteArray();
    }
    if (offset + header + valueLength > data.size()) {
        return QByteArray();
    }
    return data.mid(offset + header, valueLength);
}

int NfcCodec::capacity(const QByteArray &data)
{
    const int offset = ndefTlvOffset(data);
    const int available = data.size() - offset;
    if (available < 3) {
        return 0;
    }

    // Short length field: 0x03 + one length byte + terminator.
    int best = available - 3;
    if (best > 0xfe) {
        best = 0xfe;
    }

    // Long length field: 0x03 + 0xff + two length bytes + terminator. Only
    // worth anything once it beats the short form.
    if (available >= 5) {
        const int longForm = available - 5;
        if (longForm > best) {
            best = longForm;
        }
    }
    return best;
}

QByteArray NfcCodec::buildTagImage(const QByteArray &current,
                                   const QByteArray &ndefMessage)
{
    if (current.isEmpty()) {
        return QByteArray();
    }

    const int offset = ndefTlvOffset(current);
    if (offset > current.size()) {
        return QByteArray();
    }

    // Keep whatever came before the NDEF TLV -- on a factory fresh NTAG21x
    // that is the Lock Control TLV.
    QByteArray image = current.left(offset);

    image.append(char(TlvNdefMessage));
    if (ndefMessage.size() < 0xff) {
        image.append(char(ndefMessage.size() & 0xff));
    } else {
        image.append(char(0xff));
        image.append(char((ndefMessage.size() >> 8) & 0xff));
        image.append(char(ndefMessage.size() & 0xff));
    }
    image.append(ndefMessage);
    image.append(char(TlvTerminator));

    if (image.size() > current.size()) {
        return QByteArray();               // does not fit
    }
    if (image.size() < current.size()) {
        image.append(QByteArray(current.size() - image.size(), '\0'));
    }
    return image;
}

int NfcCodec::changedPrefixLength(const QByteArray &image,
                                  const QByteArray &current)
{
    int size = image.size();
    if (current.size() < size) {
        return size;
    }
    while (size > 0 && image.at(size - 1) == current.at(size - 1)) {
        size--;
    }
    return size;
}
