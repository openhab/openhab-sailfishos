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
TARGET = harbour-openhab

CONFIG += sailfishapp
CONFIG += link_pkgconfig

SOURCES += src/harbour-openhab.cpp\
    src/ssemanager.cpp

RESOURCES += \
    ressources.qrc

HEADERS += src/ssemanager.h

DISTFILES += qml/harbour-openhab.qml \
    harbour-openhab.desktop \
    icons/108x108/harbour-openhab.png \
    icons/128x128/harbour-openhab.png \
    icons/172x172/harbour-openhab.png \
    icons/86x86/harbour-openhab.png \
    icons/cover-background.png \
    icons/cover-background1.png \
    icons/harbour-openhab.svg \
    qml/cover/CoverPage.qml \
    qml/pages/LegalPage.qml \
    qml/pages/MainUiPage.qml \
    qml/pages/PrivacyPolicyPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/SitemapPage.qml \
    qml/pages/SelectionPage.qml \
    qml/pages/ColorPickerPage.qml \
    qml/pages/InputDialog.qml \
    qml/base/utilities/SitemapLoader.js \
    qml/base/utilities/SseEvents.js \
    qml/base/utilities/PatternFormatter.js \
    qml/base/utilities/ColorUtils.js \
    qml/base/utilities/ImageUtils.js \
    rpm/harbour-openhab.changes \
    rpm/harbour-openhab.changes.run.in \
    rpm/harbour-openhab.spec \
    translations/*.ts

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

VERSION = 0.3
RELEASE = 1
DEFINES += APP_VERSION=\\\"$$VERSION\\\"
DEFINES += APP_RELEASE=\\\"$$RELEASE\\\"

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

# German translation is enabled as an example. If you aren't
# planning to localize your app, remember to comment out the
# following TRANSLATIONS line. And also do not forget to
# modify the localized app name in the the .desktop file.
TRANSLATIONS += translations/harbour-openhab-de.ts

#support the browser engine
PKGCONFIG += qt5embedwidget

#CPP integration of Websockets
#QT += core gui qml websockets network
#QT += websockets

# Export main() symbol for mapplauncherd booster (dlsym)
QMAKE_LFLAGS += -rdynamic

LIBS += -lsailfishapp
