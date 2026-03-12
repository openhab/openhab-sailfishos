# NOTICE:
#
# Application name defined in TARGET has a corresponding QML filename.
# If name defined in TARGET is changed, the following needs to be done
# to match new name:
#   - corresponding QML filename must be changed
#   - desktop icon filename must be changed
#   - desktop filename must be changed
#   - icon definition filename in desktop file must be changed
#   - translation filenames have to be changed

# The name of your application
TARGET = openHAB

CONFIG += sailfishapp
CONFIG += link_pkgconfig

SOURCES += src/openHAB.cpp\
    src/ssemanager.cpp

RESOURCES += \
    ressources.qrc

HEADERS += src/ssemanager.h

DISTFILES += qml/openHAB.qml \
    qml/cover/CoverPage.qml \
    qml/pages/MainUiPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/SitemapPage.qml \
    qml/pages/SelectionPage.qml \
    qml/base/utilities/SitemapLoader.js \
    qml/base/utilities/SseEvents.js \
    qml/base/utilities/PatternFormatter.js \
    rpm/openHAB.changes.in \
    rpm/openHAB.changes.run.in \
    rpm/openHAB.spec \
    translations/*.ts \
    openHAB.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

VERSION = 0.1
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

# German translation is enabled as an example. If you aren't
# planning to localize your app, remember to comment out the
# following TRANSLATIONS line. And also do not forget to
# modify the localized app name in the the .desktop file.
TRANSLATIONS += translations/openHAB-de.ts

#support the browser engine
PKGCONFIG += qt5embedwidget

#CPP integration of Websockets
QT += core gui qml websockets network
QT += websockets

LIBS += -lsailfishapp
