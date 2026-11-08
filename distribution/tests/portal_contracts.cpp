#include "nmsecretagent.hpp"
#include "filechooserportal.hpp"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusArgument>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QPointer>
#include <QTemporaryDir>
#include <QThread>
#include <QUrl>
#include <filesystem>
#include <iostream>
#include <stdexcept>

using namespace hyprstack::services;
using namespace hyprstack::portals;

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
    require(done(), "Timed out waiting for a D-Bus reply");
}

class Probe : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.hyprstack.Test")
public:
    NmSecretAgent agent;
    FileChooserPortal files;
    QTemporaryDir directory;
    QString failure;
    QPointer<FileChooserRequest> pendingFile;

    void check(bool condition, const QString& message) { if (!condition) failure += message + '\n'; }
public slots:
    void Run(const QString& kind, const QDBusMessage& call) {
        call.setDelayedReply(true);
        if (kind.startsWith("nm")) {
            NMConnection connection{{"connection",{{"id","contract-test"},{"type","vpn"}}},
                {"802-11-wireless-security",{{"key-mgmt","none"},{"wep-tx-keyidx",2}}}};
            const QString setting = kind == "nm-wep" ? "802-11-wireless-security" : "vpn";
            QStringList hints;
            if (kind == "nm-multi" || kind == "nm-cancel")
                hints = {"x-vpn-message:Server asks for credentials", "password", "otp", "password"};
            else if (kind == "nm-metadata") hints = {"x-vpn-message:Information only"};
            agent.ask(connection, "/test/connection", setting, hints, kind == "nm-no-ui" ? 0 : 1, call);
            if (kind == "nm-no-ui") {
                auto list = agent.requests();
                check(list.count(&list) == 0, "Non-interactive request opened a dialog");
                return;
            }
            auto list = agent.requests();
            auto* request = list.at(&list, list.count(&list) - 1);
            check(request->key() == (kind == "nm-wep" ? "wep-key2" : "password"), "Incorrect secret key");
            if (kind == "nm-multi" || kind == "nm-cancel") {
                check(request->message() == "Server asks for credentials", "Server message was lost");
                check(request->hasNext(), "Additional secret was ignored");
                request->submit("demo-password");
                check(!request->answered() && request->key() == "otp" && !request->hasNext(), "Secret sequence advanced incorrectly");
                if (kind == "nm-cancel") request->reject();
                else request->submit("123456");
            } else request->submit("demo-value");
            return;
        }
        const auto handle = QDBusObjectPath("/org/hyprstack/test/request");
        files.add(kind == "file-cancel" ? FileChooserRequest::Action::Save : FileChooserRequest::Action::SaveMultiple,
            handle, "test.app", "Test save", {}, call);
        auto list = files.requests();
        auto* request = list.at(&list, list.count(&list) - 1);
        if (kind == "file-cancel") { pendingFile = request; return; }
        const auto dir = directory.path();
        request->accept({dir + "/report.txt", dir + "/report.txt", dir + "/.hidden", dir + "/link.txt"});
    }
};

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    try {
        Probe probe;
        auto system = QDBusConnection::systemBus();
        auto session = QDBusConnection::sessionBus();
        require(system.registerService("org.hyprstack.Tests.NM"), "Cannot own test NM service");
        require(session.registerService("org.hyprstack.Tests.Files"), "Cannot own test portal service");
        require(system.registerObject("/test", &probe, QDBusConnection::ExportAllSlots), "Cannot export NM tests");
        require(session.registerObject("/test", &probe, QDBusConnection::ExportAllSlots), "Cannot export portal tests");
        auto client = QDBusConnection::connectToBus(qEnvironmentVariable("DBUS_SESSION_BUS_ADDRESS"), "test-client");
        auto start = [&](const QString& kind) {
            auto call = QDBusMessage::createMethodCall(kind.startsWith("nm") ? "org.hyprstack.Tests.NM" : "org.hyprstack.Tests.Files",
                "/test", "org.hyprstack.Test", "Run");
            call.setArguments({kind});
            return client.asyncCall(call);
        };
        auto invoke = [&](const QString& kind) {
            QDBusPendingCallWatcher watcher(start(kind));
            until([&] { return watcher.isFinished(); });
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
            require(probe.failure.isEmpty(), probe.failure.toUtf8().constData());
            return watcher.reply();
        };
        auto reply = invoke("nm-multi");
        require(reply.type() != QDBusMessage::ErrorMessage, "Multiple secrets were rejected");
        const auto answer = qdbus_cast<NMConnection>(reply.arguments().first());
        const auto secrets = qdbus_cast<QMap<QString,QString>>(answer.value("vpn").value("secrets"));
        require(secrets.size() == 2 && secrets.value("password") == "demo-password" && secrets.value("otp") == "123456",
            "Incorrect VPN secrets reply");
        require(invoke("nm-cancel").type() == QDBusMessage::ErrorMessage, "Cancel sent a partial secret reply");
        for (const auto& kind : {"nm-metadata", "nm-wep"})
            require(invoke(kind).type() != QDBusMessage::ErrorMessage, "Fallback secret failed");
        require(invoke("nm-no-ui").errorName().endsWith("NoSecrets"), "Non-interactive request did not fail promptly");
        std::cout << "PASS: VPN metadata, multiple secrets, cancellation, WEP key index and non-interactive requests\n";
        require(probe.directory.isValid(), "Cannot create test directory");
        for (const auto& name : {"report.txt", "report (1).txt", ".hidden"}) {
            QFile file(probe.directory.filePath(name));
            require(file.open(QIODevice::WriteOnly), "Cannot seed collision test");
            file.write("existing contents");
        }
        std::filesystem::create_symlink("/nonexistent-hyprstack-test", probe.directory.filePath("link.txt").toStdString());
        reply = invoke("file-multiple");
        require(reply.type() != QDBusMessage::ErrorMessage, "SaveFiles failed");
        const auto results = qdbus_cast<QVariantMap>(reply.arguments().at(1));
        const auto uris = qdbus_cast<QStringList>(results.value("uris"));
        QStringList names;
        for (const auto& uri : uris) names.append(QFileInfo(QUrl(uri).toLocalFile()).fileName());
        require(names == QStringList{"report (2).txt", "report (3).txt", ".hidden (1)", "link (1).txt"},
            "SaveFiles did not avoid existing files, duplicate outputs or dangling symlinks");
        QFile existing(probe.directory.filePath("report.txt"));
        require(existing.open(QIODevice::ReadOnly) && existing.readAll() == "existing contents", "SaveFiles modified an existing file");
        std::cout << "PASS: SaveFiles preserves existing files and returns distinct, encoded local URIs\n";
        QDBusPendingCallWatcher pending(start("file-cancel"));
        until([&] { return !probe.pendingFile.isNull(); });
        auto close = QDBusMessage::createMethodCall("org.hyprstack.Tests.Files", "/org/hyprstack/test/request",
            "org.freedesktop.impl.portal.Request", "Close");
        QDBusPendingCallWatcher closed(client.asyncCall(close));
        until([&] { return closed.isFinished() && pending.isFinished(); });
        require(pending.reply().type() != QDBusMessage::ErrorMessage && pending.reply().arguments().size() == 2
            && pending.reply().arguments().first().toUInt() != 0, "Request.Close did not withdraw the portal request");
        std::cout << "PASS: portal Request.Close completes the pending call\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
#include "portal_contracts.moc"
