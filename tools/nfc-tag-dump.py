#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
nfc-tag-dump.py — read-only NFC tag dumper for Sailfish OS

Purpose
-------
The native openHAB client for Sailfish OS is gaining NFC support and must stay
binary-compatible with the openHAB *Android* app: a tag written on Android has
to work on Sailfish and vice versa.

What it does
------------
Talks to the Sailfish NFC daemon (nfcd) over the D-Bus system bus, waits for a
tag to be placed on the reader and writes everything it can read about that tag
into a log file.

*** THIS SCRIPT ONLY READS. ***
It never calls WriteData, Write, Acquire, Release or Deactivate. Your tag and
your phone are not modified in any way.

Requirements
------------
- Sailfish OS device with NFC hardware, NFC switched on in Settings
- Developer Mode enabled (Settings -> Developer tools) so you have a terminal
- Nothing to install: uses only python3 and dbus-send, both already on the device

How to use
----------
1. On your ANDROID phone, in the openHAB app, write a tag as you normally would
   (long-press a sitemap widget -> the "write NFC tag" action; the exact wording
   depends on the app version).
2. Copy this file to your SAILFISH device, e.g. into ~/Documents.
3. Open the Terminal app on the Sailfish device and run:

       python3 nfc-tag-dump.py

4. Hold the tag against the back of the phone when prompted. Keep it there until
   the script says it is done (a few seconds).
5. Send the resulting .log file back to the developer.

Please repeat this for TWO tags if you can:
  (a) a tag holding an item command (e.g. a light switch, ON)
  (b) a tag holding a sitemap link

Privacy note
------------
The log contains the item name and label you put on the tag, plus the tag's
serial number. It does NOT contain your server address, credentials or any
other data from your installation. Feel free to open the .log in a text editor
and check — it is plain text — before sending it.

Usage
-----
    python3 nfc-tag-dump.py [--wait SECONDS] [--out FILE] [--no-prompt]
    python3 nfc-tag-dump.py --instructions

License: EPL-2.0, same as the openHAB Sailfish OS client.
"""

import argparse
import datetime
import os
import re
import subprocess
import sys
import time

NFC_SERVICE = "org.sailfishos.nfc.daemon"
NFC_SETTINGS_SERVICE = "org.sailfishos.nfc.settings"

IFACE_DAEMON = "org.sailfishos.nfc.Daemon"
IFACE_ADAPTER = "org.sailfishos.nfc.Adapter"
IFACE_TAG = "org.sailfishos.nfc.Tag"
IFACE_NDEF = "org.sailfishos.nfc.NDEF"
IFACE_TYPE2 = "org.sailfishos.nfc.TagType2"
IFACE_SETTINGS = "org.sailfishos.nfc.Settings"

_log_lines = []


def log(text=""):
    """Print to the terminal and remember for the log file."""
    print(text)
    _log_lines.append(text)


def log_quiet(text=""):
    """Only remember for the log file, do not clutter the terminal."""
    _log_lines.append(text)


# --------------------------------------------------------------------------
# D-Bus plumbing (via dbus-send, so no python3-dbus dependency is needed)
# --------------------------------------------------------------------------

def dbus_call(service, path, interface, method, timeout_ms=5000):
    """Call a D-Bus method without arguments. Returns (ok, output_text)."""
    cmd = [
        "dbus-send", "--system", "--print-reply",
        "--reply-timeout=%d" % timeout_ms,
        "--dest=%s" % service, path,
        "%s.%s" % (interface, method),
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=(timeout_ms / 1000.0) + 5)
    except FileNotFoundError:
        return False, "dbus-send not found on this device"
    except subprocess.TimeoutExpired:
        return False, "timeout"
    out = proc.stdout.decode("utf-8", "replace").strip()
    return proc.returncode == 0, out


def parse_object_paths(text):
    return re.findall(r'object path "([^"]+)"', text)


def parse_strings(text):
    return re.findall(r'string "([^"]*)"', text)


READ_ALL_DATA_ATTEMPTS = 5

_HEX_BYTE = re.compile(r'^[0-9a-fA-F]{2}$')


def parse_bytes(text):
    """
    Extract a D-Bus byte array ('ay') from a dbus-send reply.

    dbus-send prints byte arrays as space separated *hex* pairs, wrapped over
    as many lines as the array needs:

        array of bytes [
           5a e5 11 e2 08 41 89
        ]

    A single byte outside an array is printed in decimal ('byte 0'), and some
    builds use that decimal form inside arrays as well, so both are accepted.
    An empty array yields b"".
    """
    out = bytearray()
    for block in re.findall(r'array of bytes\s*\[(.*?)\]', text, re.S):
        for token in block.split():
            if _HEX_BYTE.match(token):
                out.append(int(token, 16))
    if out:
        return bytes(out)
    # Fallback: decimal 'byte N' entries.
    return bytes(int(v) for v in re.findall(r'\bbyte\s+(\d+)', text))


def parse_first_number(text):
    m = re.search(r'\b(?:uint32|int32|uint16|int16|uint64|int64)\s+(\d+)', text)
    return int(m.group(1)) if m else None


def parse_bool(text):
    m = re.search(r'\bboolean\s+(true|false)', text)
    if not m:
        return None
    return m.group(1) == "true"


# --------------------------------------------------------------------------
# Formatting helpers
# --------------------------------------------------------------------------

def hexdump(data, indent="    "):
    """Classic offset / hex / ascii dump."""
    lines = []
    for off in range(0, len(data), 16):
        chunk = data[off:off + 16]
        hexpart = " ".join("%02x" % b for b in chunk)
        hexpart = hexpart.ljust(16 * 3 - 1)
        asciipart = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append("%s%04x  %s  |%s|" % (indent, off, hexpart, asciipart))
    return "\n".join(lines) if lines else indent + "(empty)"


def as_c_array(data):
    """Byte array in a form that can be pasted straight into a unit test."""
    parts = ["0x%02x" % b for b in data]
    rows = [", ".join(parts[i:i + 12]) for i in range(0, len(parts), 12)]
    return "{ " + ",\n  ".join(rows) + " }"


def section(title):
    log("")
    log("=" * 72)
    log(title)
    log("=" * 72)


# --------------------------------------------------------------------------
# Probing steps
# --------------------------------------------------------------------------

def dump_environment():
    section("1. ENVIRONMENT")
    for path in ("/etc/sailfish-release", "/etc/os-release"):
        if os.path.exists(path):
            log("--- %s ---" % path)
            try:
                with open(path, "r") as fh:
                    for line in fh:
                        line = line.rstrip()
                        # Skip anything that could identify the device owner.
                        if line and not line.lower().startswith("home_url"):
                            log("  " + line)
            except OSError as exc:
                log("  (could not read: %s)" % exc)
            break
    ok, out = dbus_call(NFC_SETTINGS_SERVICE, "/", IFACE_SETTINGS, "GetEnabled")
    log("")
    log("NFC system setting enabled: %s" % (parse_bool(out) if ok else "unknown (%s)" % out))


def dump_daemon():
    section("2. NFC DAEMON")
    for method in ("GetAll6", "GetAll5", "GetAll4", "GetAll3", "GetAll2", "GetAll"):
        ok, out = dbus_call(NFC_SERVICE, "/", IFACE_DAEMON, method)
        if ok:
            log("Daemon.%s() raw reply:" % method)
            log_quiet(out)
            log("  (full reply in log file)")
            break
    else:
        log("No Daemon.GetAll* method answered — this is unexpected.")

    ok, out = dbus_call(NFC_SERVICE, "/", IFACE_DAEMON, "GetAdapters")
    if not ok:
        log("")
        log("!! Daemon.GetAdapters() failed:")
        log(out)
        log("")
        log("   Either nfcd is not running, or this device has no NFC hardware,")
        log("   or the call was denied. Try again with:  devel-su python3 %s"
            % os.path.basename(sys.argv[0]))
        return []

    adapters = parse_object_paths(out)
    log("Adapters: %s" % (", ".join(adapters) if adapters else "NONE"))
    for adapter in adapters:
        for method in ("GetEnabled", "GetPowered", "GetMode"):
            ok, out = dbus_call(NFC_SERVICE, adapter, IFACE_ADAPTER, method)
            value = out.splitlines()[-1].strip() if ok and out else "?"
            log("  %s.%s = %s" % (adapter, method, value))
    return adapters


def wait_for_tag(adapters, wait_seconds):
    section("3. WAITING FOR TAG")
    log(">>> Please hold the NFC tag against the back of the phone now. <<<")
    log("    (waiting up to %d seconds)" % wait_seconds)
    log("")
    deadline = time.time() + wait_seconds
    while time.time() < deadline:
        for adapter in adapters:
            ok, out = dbus_call(NFC_SERVICE, adapter, IFACE_ADAPTER, "GetTags")
            if ok:
                tags = parse_object_paths(out)
                if tags:
                    log("Tag detected: %s" % ", ".join(tags))
                    return tags
        time.sleep(0.3)
    log("No tag appeared within %d seconds." % wait_seconds)
    return []


def dump_tag(tag_path):
    section("4. TAG %s" % tag_path)

    for method in ("GetAll3", "GetAll2", "GetAll"):
        ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TAG, method)
        if ok:
            log("Tag.%s() raw reply captured in log file." % method)
            log_quiet("--- Tag.%s() ---" % method)
            log_quiet(out)
            break

    for method in ("GetPresent", "GetTechnology", "GetProtocol", "GetType"):
        ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TAG, method)
        value = out.splitlines()[-1].strip() if ok and out else "?"
        log("  Tag.%s = %s" % (method, value))

    ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TAG, "GetInterfaces")
    interfaces = parse_strings(out) if ok else []
    log("  Tag.GetInterfaces = %s" % (interfaces or "none"))

    ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TAG, "GetNdefRecords")
    records = parse_object_paths(out) if ok else []
    log("  Tag.GetNdefRecords = %s" % (records or "none"))

    # The raw memory read is both the most valuable and the most fragile part
    # of this dump: nfcd can only talk to the tag while it is actually in the
    # field. Do it first, directly after detection, instead of after a dozen
    # NDEF round trips.
    if IFACE_TYPE2 in interfaces:
        dump_type2(tag_path)
    else:
        log("")
        log("  Tag does not expose %s — no raw memory dump possible." % IFACE_TYPE2)
        log("  (That is itself an interesting result, please still send the log.)")

    for index, record in enumerate(records):
        dump_ndef_record(record, index)


def dump_ndef_record(record_path, index):
    section("6.%d NDEF RECORD %s" % (index + 1, record_path))

    ok, out = dbus_call(NFC_SERVICE, record_path, IFACE_NDEF, "GetAll")
    if ok:
        log_quiet("--- NDEF.GetAll() ---")
        log_quiet(out)
        log("  NDEF.GetAll() raw reply captured in log file.")

    for method in ("GetFlags", "GetTypeNameFormat", "GetTnf"):
        ok, out = dbus_call(NFC_SERVICE, record_path, IFACE_NDEF, method)
        if ok:
            log("  NDEF.%s = %s" % (method, out.splitlines()[-1].strip()))

    for method, label in (("GetType", "type"), ("GetId", "id"),
                          ("GetPayload", "payload"), ("GetRawData", "raw record")):
        ok, out = dbus_call(NFC_SERVICE, record_path, IFACE_NDEF, method)
        if not ok:
            log("  NDEF.%s failed: %s" % (method, out.splitlines()[-1] if out else "?"))
            continue
        data = parse_bytes(out)
        log("")
        log("  NDEF %s (%d bytes):" % (label, len(data)))
        log(hexdump(data, indent="      "))
        if label == "payload" and len(data) > 1:
            # A URI record starts with the abbreviation code, rest is UTF-8.
            log("      URI prefix code : 0x%02x" % data[0])
            log("      URI text        : %r" % data[1:].decode("utf-8", "replace"))
        if label in ("payload", "raw record"):
            log("      as C array      :")
            log("      " + as_c_array(data).replace("\n", "\n      "))


def dump_type2(tag_path):
    section("5. TYPE 2 RAW MEMORY %s" % tag_path)

    ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TYPE2, "GetAll")
    if ok:
        log_quiet("--- TagType2.GetAll() ---")
        log_quiet(out)

    for method in ("GetBlockSize", "GetDataSize"):
        ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TYPE2, method)
        log("  TagType2.%s = %s" % (method, parse_first_number(out) if ok else "?"))

    ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TYPE2, "GetSerial")
    if ok:
        serial = parse_bytes(out)
        log("  TagType2.GetSerial = %s" % " ".join("%02x" % b for b in serial))

    # ReadAllData needs the tag to be in the field *right now*. Every dbus-send
    # is its own short lived bus connection, so nothing keeps the tag activated
    # between calls and a single miss is normal. Retry a few times and ask the
    # operator to keep holding the tag.
    log("")
    log("  Reading raw memory — please keep holding the tag against the phone.")
    data = b""
    last_error = "?"
    for attempt in range(1, READ_ALL_DATA_ATTEMPTS + 1):
        ok, out = dbus_call(NFC_SERVICE, tag_path, IFACE_TYPE2, "ReadAllData",
                            timeout_ms=15000)
        if ok:
            data = parse_bytes(out)
            log_quiet("--- TagType2.ReadAllData() (attempt %d) ---" % attempt)
            log_quiet(out)
            if data:
                break
            last_error = "reply contained 0 bytes"
        else:
            last_error = out.splitlines()[-1] if out else "?"
        log("  attempt %d/%d failed: %s"
            % (attempt, READ_ALL_DATA_ATTEMPTS, last_error))
        time.sleep(0.5)

    if not data:
        log("")
        log("  TagType2.ReadAllData did not return any data: %s" % last_error)
        log("  This may simply mean the tag left the field, or that nfcd cannot")
        log("  read this tag's data area. Please note whether you kept the tag")
        log("  on the phone the whole time, and send the log either way.")
        return
    log("")
    log("  ReadAllData — %d bytes of the tag's data area:" % len(data))
    log(hexdump(data, indent="      "))
    log("")
    log("  as C array:")
    log("  " + as_c_array(data).replace("\n", "\n  "))

    decode_tlv_chain(data)


TLV_NAMES = {
    0x00: "NULL",
    0x01: "Lock Control",
    0x02: "Memory Control",
    0x03: "NDEF Message",
    0xfd: "Proprietary",
    0xfe: "Terminator",
}


def decode_tlv_chain(data):
    """
    Walk the Type 2 TLV chain.

    The NDEF Message TLV is NOT necessarily at offset 0: NTAG21x tags ship from
    the factory with a Lock Control TLV (01 03 a0 0c 34) in front of it, and a
    well behaved writer keeps that TLV where it is. Anything that only looks at
    offset 0 reports "no NDEF" on a perfectly normal tag.
    """
    log("")
    log("  TLV chain:")
    offset = 0
    found_ndef = False
    while offset < len(data):
        tag = data[offset]
        name = TLV_NAMES.get(tag, "unknown")

        if tag == 0xfe:
            log("    0x%03x  0x%02x %-14s — end of chain" % (offset, tag, name))
            break
        if tag == 0x00:
            offset += 1
            continue
        if offset + 1 >= len(data):
            log("    0x%03x  0x%02x %-14s — truncated, no length byte"
                % (offset, tag, name))
            break

        # One byte length, or 0xff followed by a two byte length.
        if data[offset + 1] == 0xff and offset + 3 < len(data):
            length = (data[offset + 2] << 8) | data[offset + 3]
            header = 4
        else:
            length = data[offset + 1]
            header = 2

        body = data[offset + header:offset + header + length]
        log("    0x%03x  0x%02x %-14s length %d" % (offset, tag, name, length))

        if tag == 0x03:
            found_ndef = True
            log("")
            if length == 0:
                log("  NDEF message is EMPTY (factory fresh or erased tag).")
            else:
                log("  NDEF message bytes (%d):" % len(body))
                log(hexdump(body, indent="      "))
                log("")
                log("  NDEF message as C array:")
                log("  " + as_c_array(body).replace("\n", "\n  "))
            log("")

        offset += header + length

    if not found_ndef:
        log("    (no NDEF Message TLV found in the chain)")


# --------------------------------------------------------------------------

def ask_notes():
    log("")
    log("A few questions so we can match the dump to what you wrote.")
    log("Press Enter to skip any of them.")
    log("")
    questions = [
        ("openHAB Android app version", "android_app_version"),
        ("What did you write on this tag? (item command / sitemap link)", "tag_kind"),
        ("Item name, if applicable", "item_name"),
        ("Command / state, if applicable", "command"),
        ("Tag hardware, if known (e.g. NTAG213)", "tag_hw"),
    ]
    answers = []
    for prompt, key in questions:
        try:
            value = input("  %s: " % prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("")
            value = ""
        answers.append((key, value))
    log_quiet("")
    log_quiet("--- notes from the operator ---")
    for key, value in answers:
        log_quiet("%-24s: %s" % (key, value))


def main():
    parser = argparse.ArgumentParser(
        description="Read-only NFC tag dumper for Sailfish OS (openHAB).")
    parser.add_argument("--wait", type=int, default=60,
                        help="seconds to wait for a tag (default: 60)")
    parser.add_argument("--out", default=None, help="log file to write")
    parser.add_argument("--no-prompt", action="store_true",
                        help="do not ask the questions at the end")
    parser.add_argument("--instructions", action="store_true",
                        help="print the full instructions and exit")
    args = parser.parse_args()

    if args.instructions:
        print(__doc__)
        return 0

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = args.out or os.path.join(os.path.expanduser("~/Downloads"),
                                        "nfc-tag-dump-%s.log" % stamp)

    log("openHAB Sailfish OS — NFC tag dump")
    log("Generated: %s" % datetime.datetime.now().isoformat(timespec="seconds"))
    log("This script only reads. Your tag is not modified.")

    dump_environment()
    adapters = dump_daemon()

    if adapters:
        tags = wait_for_tag(adapters, args.wait)
        for tag in tags:
            dump_tag(tag)
    else:
        log("")
        log("Stopping: no NFC adapter to talk to.")

    if not args.no_prompt:
        ask_notes()

    try:
        with open(out_path, "w") as fh:
            fh.write("\n".join(_log_lines) + "\n")
        print("")
        print("=" * 72)
        print("Log written to: %s" % out_path)
        print("Please send this file back to the developers. Thank you!")
        print("=" * 72)
    except OSError as exc:
        print("")
        print("Could not write the log file (%s)." % exc)
        print("Please copy the terminal output above by hand instead.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
