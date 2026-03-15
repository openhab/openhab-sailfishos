#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickView>
#include "ssemanager.h"
#include <QNetworkAccessManager>

int main(int argc, char *argv[])
{
    qRegisterMetaType<QNetworkAccessManager::NetworkAccessibility>("QNetworkAccessManager::NetworkAccessibility");
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setApplicationVersion(APP_VERSION);
    QQuickView* view = SailfishApp::createView();

    SSEManager SSEManager;
    // Exposes the C++ instance as "sseManager" in QML
    view->rootContext()->setContextProperty("sseManager", &SSEManager);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
