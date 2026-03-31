# ──────────────────────────────────────────────
# C++ unit test project for SSEManager
# Build:  cd tests/unittest && qmake5 && make
# Run:    ./tst_ssemanager
# ──────────────────────────────────────────────

QT       += testlib network
QT       -= gui

CONFIG   += testcase console c++11
CONFIG   -= app_bundle

TARGET    = tst_ssemanager
TEMPLATE  = app

INCLUDEPATH += ../../src

SOURCES  += tst_ssemanager.cpp \
            ../../src/ssemanager.cpp

HEADERS  += ../../src/ssemanager.h

