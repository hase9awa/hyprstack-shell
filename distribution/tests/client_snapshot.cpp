#include "hyprextras.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJSEngine>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTemporaryDir>
#include <QThread>
#include <iostream>
#include <stdexcept>

using hyprstack::services::hypr::HyprExtras;

static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename Predicate> static void until(Predicate done) {
    QElapsedTimer timer;
    timer.start();
    while (!done() && timer.elapsed() < 5000) {
        QCoreApplication::processEvents();
        QThread::msleep(1);
    }
    require(done(), "Timed out waiting for the client snapshot");
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    try {
        QTemporaryDir runtime;
        require(runtime.isValid(), "Cannot create the mock runtime");
        const auto dir = runtime.path() + "/hypr/snapshot-test";
        QDir().mkpath(dir);
        qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
        qputenv("HYPRLAND_INSTANCE_SIGNATURE", "snapshot-test");
        QLocalServer commands, events;
        require(commands.listen(dir + "/.socket.sock"), "Cannot listen for commands");
        require(events.listen(dir + "/.socket2.sock"), "Cannot listen for events");
        const QByteArray mainWindow = R"({"address":"0x1","stableId":"one","class":"com.ayugram.desktop","mapped":true,"hidden":false,"workspace":{"id":2},"fullscreen":0})";
        const QByteArray viewer = R"({"address":"0x2","stableId":"two","class":"AyuGram","mapped":true,"hidden":false,"workspace":{"id":2},"fullscreen":2})";
        const auto stale = '[' + mainWindow + ',' + viewer + ']';
        QByteArray current = '[' + mainWindow + ']';
        QLocalSocket* delayed = nullptr;
        int requests = 0;
        const auto reply = [](QLocalSocket* socket, const QByteArray& data) {
            socket->write(data);
            socket->disconnectFromServer();
        };
        QObject::connect(&commands, &QLocalServer::newConnection, [&] {
            while (commands.hasPendingConnections()) {
                auto* socket = commands.nextPendingConnection();
                QObject::connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
                    const auto command = socket->readAll();
                    if (command == "j/clients") {
                        if (++requests == 1) delayed = socket;
                        else reply(socket, current);
                    } else reply(socket, command == "j/descriptions" ? "[]" : "{}");
                });
            }
        });
        HyprExtras extras;
        until([&] { return delayed != nullptr; });
        require(!extras.clientsReady(), "An unfinished snapshot must not hide existing windows");
        // A fullscreen viewer closes while the older query is still in flight.
        for (int i = 0; i < 50; ++i) extras.refreshClients();
        reply(delayed, stale);
        until([&] { return requests == 2 && extras.clientsReady() && extras.clients().size() == 1; });
        require(!extras.clients().contains("0x2"), "The closed viewer survived the trailing snapshot");
        require(requests == 2, "A burst should be coalesced into one trailing query");

        QFile helper(QString::fromLocal8Bit(argv[1]));
        require(helper.open(QIODevice::ReadOnly), "Cannot read ClientSnapshot.js");
        QJSEngine js;
        require(!js.evaluate(QString::fromUtf8(helper.readAll())).isError(), "Cannot load snapshot helpers");
        js.globalObject().setProperty("clients", js.toScriptValue(extras.clients()));
        js.evaluate("var wrappers = " + QString::fromUtf8(stale) + ".map(w => ({ lastIpcObject: w }));");
        const auto check = [&](const QString& expression) {
            const auto result = js.evaluate(expression);
            if (result.isError() || !result.toBool()) throw std::runtime_error(expression.toStdString());
        };
        check("wrappers.filter(w => clientData(w, clients, true)).length === 1");
        check("!hasFullscreen(2, clients, true, wrappers)");
        check("hasFullscreen(2, clients, false, wrappers)");
        check("clientData(wrappers[0], clients, false) !== null");
        check("clientData({lastIpcObject:{address:'0x1',stableId:'reused'}}, clients, true) === null");
        check("clientData(null, clients, true) === null");
        check("(() => { const c = JSON.parse(JSON.stringify(clients)); c['0x1'].fullscreen=2; return hasFullscreen(2,c,true,wrappers) && !hasFullscreen(3,c,true,wrappers); })()");
        check("(() => { const c = JSON.parse(JSON.stringify(clients)); c['0x1'].fullscreen=1; return !hasFullscreen(2,c,true,wrappers); })()");
        check("(() => { const c = JSON.parse(JSON.stringify(clients)); c['0x1'].fullscreen=2; c['0x1'].hidden=true; return !hasFullscreen(2,c,true,wrappers); })()");

        current = "invalid response";
        extras.refreshClients();
        until([&] { return requests == 3; });
        // Flush the invalid response, then a valid empty snapshot. Invalid data
        // must preserve the last valid state, while [] must remove every window.
        QElapsedTimer settle;
        settle.start();
        while (settle.elapsed() < 30) QCoreApplication::processEvents();
        require(extras.clients().size() == 1, "A malformed response discarded a valid snapshot");
        current = "[]";
        extras.refreshClients();
        until([&] { return requests == 4 && extras.clients().isEmpty(); });
        require(extras.clientsReady(), "An empty client list is still an authoritative snapshot");
        js.globalObject().setProperty("clients", js.toScriptValue(extras.clients()));
        check("wrappers.filter(w => clientData(w, clients, true)).length === 0");
        check("!hasFullscreen(2, clients, true, wrappers)");
        std::cout << "PASS: delayed replies, coalescing, closed viewers, fullscreen, address reuse, invalid and empty snapshots\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
