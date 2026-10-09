# ──────────────────────────────────────────────
# C++ unit test project for NfcCodec
#
# Deliberately separate from unittest.pro: NfcCodec must stay linkable
# without QtNetwork and without a D-Bus connection, so that the %check
# block in the RPM spec can run it on a build host that has neither NFC
# hardware nor a system bus.
#
# Build:  cd tests/unittest && qmake5 nfccodec.pro && make
# Run:    ./tst_nfccodec
# ──────────────────────────────────────────────

QT       += testlib
QT       -= gui

CONFIG   += testcase console c++11
CONFIG   -= app_bundle

TARGET    = tst_nfccodec
TEMPLATE  = app

INCLUDEPATH += ../../src

SOURCES  += tst_nfccodec.cpp \
            ../../src/nfccodec.cpp

HEADERS  += ../../src/nfccodec.h
