# ──────────────────────────────────────────────
# JavaScript logic test project  (QTest + QJSEngine)
#
# Evaluates production JS files via QJSEngine – no Qt Quick scene graph
# or OpenGL required.  Runs reliably in headless / offscreen environments.
#
# Build:  cd tests/qmltest && qmake5 && make
# Run:    ./tst_qml
# ──────────────────────────────────────────────

QT       += testlib qml
QT       -= gui

CONFIG   += testcase console c++11
CONFIG   -= app_bundle

TARGET    = tst_qml
TEMPLATE  = app

SOURCES  += tst_jslogic.cpp

# Source root so the test can locate the JS files at runtime
DEFINES  += SRCDIR=\\\"$$PWD\\\"

