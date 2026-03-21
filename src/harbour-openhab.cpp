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

int Q_DECL_EXPORT main(int argc, char *argv[])
{
    qRegisterMetaType<QNetworkAccessManager::NetworkAccessibility>("QNetworkAccessManager::NetworkAccessibility");
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setApplicationVersion(APP_VERSION "-" APP_RELEASE);
    QQuickView* view = SailfishApp::createView();

    SSEManager sseManagerInstance;
    // Exposes the C++ instance as "sseManager" in QML
    view->rootContext()->setContextProperty("sseManager", &sseManagerInstance);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
