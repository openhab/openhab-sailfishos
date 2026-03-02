#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext> // Benötigt für setContextProperty
#include "ssemanager.h" // Ihre neue Klasse
#include <QNetworkAccessManager>

int main(int argc, char *argv[])
{
    // SailfishApp::main() will display "qml/openHAB.qml", if you need more
    // control over initialization, you can use:
    //
    //   - SailfishApp::application(int, char *[]) to get the QGuiApplication *
    //   - SailfishApp::createView() to get a new QQuickView * instance
    //   - SailfishApp::pathTo(QString) to get a QUrl to a resource file
    //   - SailfishApp::pathToMainQml() to get a QUrl to the main QML file
    //
    // To display the view, call "show()" (will show fullscreen on device).
    qRegisterMetaType<QNetworkAccessManager::NetworkAccessibility>("QNetworkAccessManager::NetworkAccessibility");
    QGuiApplication *app = SailfishApp::application(argc, argv);
    //QQmlApplicationEngine engine;
    QQuickView* view = SailfishApp::createView(); // Erstellt die View

    SSEManager SSEManager;
    // Exponiert die C++-Instanz als "sseManager" in QML
    //engine.rootContext()->setContextProperty("sseManager", &SSEManager);

    view->rootContext()->setContextProperty("sseManager", &SSEManager);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
