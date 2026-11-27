#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include "ssemanager.h"
#include "nfcmanager.h"
#include "cloud/connectionmanager.h"
#include "cloud/remoteauth.h"
#include <QNetworkAccessManager>

int Q_DECL_EXPORT main(int argc, char *argv[])
{
    qRegisterMetaType<QNetworkAccessManager::NetworkAccessibility>("QNetworkAccessManager::NetworkAccessibility");
    qRegisterMetaType<QNetworkAccessManager::NetworkAccessibility>("NetworkAccessibility");
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setApplicationVersion(APP_VERSION "-" APP_RELEASE);
    QQuickView* view = SailfishApp::createView();

    // Adds the remote credentials to QML's own requests (icons, charts,
    // images) -- must be set before the engine creates its first NAM.
    RemoteAuthNamFactory namFactory;
    view->engine()->setNetworkAccessManagerFactory(&namFactory);

    // Local or remote (openHAB Cloud): QML reads the active connection from
    // here. Configured from Settings.qml in harbour-openhab.qml.
    ConnectionManager connectionManagerInstance;
    view->rootContext()->setContextProperty("connection", &connectionManagerInstance);

    SSEManager sseManagerInstance;
    // Exposes the C++ instance as "sseManager" in QML
    view->rootContext()->setContextProperty("sseManager", &sseManagerInstance);

    // NFC (nfcd via the D-Bus system bus). Constructing it is harmless on
    // devices without NFC -- "available" simply stays false and the UI hides
    // the feature.
    NfcManager nfcManagerInstance;
    view->rootContext()->setContextProperty("nfcManager", &nfcManagerInstance);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
