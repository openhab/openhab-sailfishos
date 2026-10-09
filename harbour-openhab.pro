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

# NFC talks to nfcd over the D-Bus system bus
QT += dbus

SOURCES += src/harbour-openhab.cpp\
    src/ssemanager.cpp \
    src/nfccodec.cpp \
    src/nfcmanager.cpp

RESOURCES += \
    ressources.qrc

HEADERS += src/ssemanager.h \
    src/nfccodec.h \
    src/nfcmanager.h

DISTFILES += qml/harbour-openhab.qml \
    .editorconfig \
    harbour-openhab.desktop \
    icons/108x108/harbour-openhab.png \
    icons/128x128/harbour-openhab.png \
    icons/172x172/harbour-openhab.png \
    icons/86x86/harbour-openhab.png \
    icons/cover-background.png \
    icons/cover-background1.png \
    icons/harbour-openhab.svg \
    qml/components/CoverActionIconComboBox.qml \
    qml/cover/CoverPage.qml \
    qml/pages/LegalPage.qml \
    qml/pages/MainUiPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/SitemapPage.qml \
    qml/pages/SelectionPage.qml \
    qml/pages/ColorPickerPage.qml \
    qml/pages/InputDialog.qml \
    qml/pages/NfcPage.qml \
    qml/pages/NfcWritePage.qml \
    qml/pages/NfcCommandPage.qml \
    qml/pages/SitemapSelectionPage.qml \
    qml/components/NotificationManager.qml \
    qml/components/SitemapPullDownMenu.qml \
    qml/base/Settings.qml \
    qml/base/data/item-commands.json \
    qml/base/utilities/NfcUri.js \
    qml/base/utilities/OpenHabApi.js \
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

VERSION = 0.4
RELEASE = 1
DEFINES += APP_VERSION=\\\"$$VERSION\\\"
DEFINES += APP_RELEASE=\\\"$$RELEASE\\\"

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

TRANSLATIONS += translations/harbour-openhab-*.ts

#support the browser engine
PKGCONFIG += qt5embedwidget

#CPP integration of Websockets
#QT += core gui qml websockets network
#QT += websockets

# Export main() symbol for mapplauncherd booster (dlsym)
QMAKE_LFLAGS += -rdynamic

LIBS += -lsailfishapp
