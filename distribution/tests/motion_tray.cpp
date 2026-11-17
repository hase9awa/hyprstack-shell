#include <QApplication>
#include <QIcon>
#include <QMenu>
#include <QPainter>
#include <QSystemTrayIcon>

// Real StatusNotifierItem/DBusMenu fixtures on the test's private session bus.
int main(int argc, char** argv) {
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    const bool large = app.arguments().contains(QStringLiteral("large"));
    app.setApplicationName(large ? QStringLiteral("motion-tray-large") : QStringLiteral("motion-tray-small"));
    QMenu menu;
    for (int i = 0; i < (large ? 10 : 3); ++i)
        menu.addAction((large ? QStringLiteral("Long menu fixture action ") : QStringLiteral("Action ")) + QString::number(i + 1));
    QPixmap image(24, 24);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setBrush(large ? QColor("#c7a2ed") : QColor("#b7c97f"));
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(3, 3, 18, 18);
    painter.end();
    QSystemTrayIcon tray{QIcon(image)};
    tray.setToolTip(app.applicationName());
    tray.setContextMenu(&menu);
    tray.show();
    return app.exec();
}
