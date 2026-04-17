#include <QApplication>
#include <QStandardPaths>

#include "MainWindow.h"

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("iDOpus"));
    QApplication::setOrganizationName(QStringLiteral("tenk.se"));

    const QString home =
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation);

    MainWindow w(home);
    w.resize(900, 600);
    w.show();
    return app.exec();
}
