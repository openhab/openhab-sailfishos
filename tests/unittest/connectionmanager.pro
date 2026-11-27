# ──────────────────────────────────────────────
# C++ unit test project for ConnectionManager / RemoteAuth
#
# Uses small HTTP servers on 127.0.0.1 only, no internet access needed.
#
# Build:  cd tests/unittest && qmake5 connectionmanager.pro && make
# Run:    ./tst_connectionmanager
# ──────────────────────────────────────────────

QT       += testlib network qml
QT       -= gui

CONFIG   += testcase console c++11
CONFIG   -= app_bundle

TARGET    = tst_connectionmanager
TEMPLATE  = app

INCLUDEPATH += ../../src

SOURCES  += tst_connectionmanager.cpp \
            ../../src/cloud/connectionmanager.cpp \
            ../../src/cloud/remoteauth.cpp

HEADERS  += ../../src/cloud/connectionmanager.h \
            ../../src/cloud/remoteauth.h
