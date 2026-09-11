#ifndef NFCCODEC_H
#define NFCCODEC_H

#include <QByteArray>
#include <QString>

/**
 * Pure NDEF / Type 2 TLV codec.
 *
 * Everything in here is a byte transformation: no D-Bus, no network, no GUI.
 * That is deliberate -- this class is linked into tests/unittest and runs on
 * the build host, where neither NFC hardware nor a system bus exists.
 *
 * The tag layout this class produces follows what a factory fresh tag
 * actually contains:
 * the data area of a Type 2 tag is a TLV chain, and a factory fresh NTAG21x
 * starts with a Lock Control TLV that we must NOT overwrite -- unlike
 * nfcd's own ndef-write tool, which zeroes the whole area.
 */
class NfcCodec
{
public:
    /** NDEF TNF (type name format) values. */
    enum Tnf {
        TnfEmpty      = 0x00,
        TnfWellKnown  = 0x01
    };

    /** TLV types found in the data area of a Type 2 tag. */
    enum TlvType {
        TlvNull           = 0x00,
        TlvLockControl    = 0x01,
        TlvMemoryControl  = 0x02,
        TlvNdefMessage    = 0x03,
        TlvProprietary    = 0xfd,
        TlvTerminator     = 0xfe
    };

    // ---- NDEF record level -------------------------------------------------

    /**
     * Build a complete NDEF message containing exactly one well-known URI
     * record. Uses the short record form while the payload fits into one
     * length byte and the long form beyond that.
     */
    static QByteArray buildUriMessage(const QString &uri);

    /**
     * Decode the payload of a URI record back into the full URI text.
     * Resolves the leading abbreviation code. Returns an empty string when
     * the payload is empty.
     */
    static QString uriFromPayload(const QByteArray &payload);

    /**
     * Extract the URI from a whole NDEF message (as opposed to a single
     * record payload). Returns an empty string when the first record is not
     * a well-known URI record.
     */
    static QString uriFromMessage(const QByteArray &message);

    // ---- Type 2 TLV level --------------------------------------------------

    /**
     * Offset of the first byte that is NOT part of a leading Lock Control,
     * Memory Control, Proprietary or Null TLV -- in other words, where the
     * NDEF Message TLV belongs. Returns data.size() when the chain runs off
     * the end.
     */
    static int ndefTlvOffset(const QByteArray &data);

    /**
     * The NDEF message stored in a raw data area, or an empty array when the
     * chain holds no NDEF Message TLV (or an empty one).
     */
    static QByteArray ndefMessageFromData(const QByteArray &data);

    /**
     * Largest NDEF message (in bytes) that fits into a data area of this
     * shape, taking the leading TLVs and the TLV framing into account.
     */
    static int capacity(const QByteArray &data);

    /**
     * Build the full replacement image for the data area: leading TLVs copied
     * verbatim from `current`, then the NDEF Message TLV, a terminator, and
     * zero padding up to the original length.
     *
     * Returns an empty array when the message does not fit -- callers must
     * check for that and fall back to the short URI form.
     */
    static QByteArray buildTagImage(const QByteArray &current,
                                    const QByteArray &ndefMessage);

    /**
     * Number of leading bytes that actually differ and therefore have to be
     * written. Mirrors write_ndef_data_diff() from nfcd's ndef-write.c: the
     * write is always a prefix starting at offset 0.
     */
    static int changedPrefixLength(const QByteArray &image,
                                   const QByteArray &current);

private:
    NfcCodec() {}
};

#endif // NFCCODEC_H
