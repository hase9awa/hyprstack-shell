#include "nmsecretagent.hpp"
#include "filechooserportal.hpp"
#include "filevolumes.hpp"
#include "filesystemmodel.hpp"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusArgument>
#include <QDBusContext>
#include <QTimer>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QPointer>
#include <QPersistentModelIndex>
#include <QTemporaryDir>
#include <QThread>
#include <QUrl>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <algorithm>

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

class FakeDisks : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.DBus.ObjectManager")
public:
    VolumeObjects objects;
public slots:
    VolumeObjects GetManagedObjects() { return objects; }
signals:
    void InterfacesAdded(const QDBusObjectPath& path, const VolumeInterfaces& interfaces);
};

class FakeMount : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.UDisks2.Filesystem")
public:
    QString path;
    bool deny = false;
    int calls = 0;
public slots:
    QString Mount(const QVariantMap& options) {
        ++calls;
        require(options.isEmpty(), "Mount forced filesystem options");
        if (deny) {
            sendErrorReply("org.freedesktop.UDisks2.Error.NotAuthorized", "Test: permission denied");
            return {};
        }
        const auto call = message();
        const auto bus = connection();
        setDelayedReply(true);
        QTimer::singleShot(100, this, [this, call, bus] {
            bus.send(call.createReply(path));
        });
        return {};
    }
};

static void checkVolumes() {
    auto bus = QDBusConnection::connectToBus(qEnvironmentVariable("DBUS_SYSTEM_BUS_ADDRESS"), "fake-udisks");
    FileVolumes volumes; // Registers the wire types used by the fake service too.
    FakeDisks disks;
    FakeMount mount;
    QTemporaryDir directory;
    require(directory.isValid(), "Cannot create mounted-volume fixture");
    mount.path = directory.path();
    const QString device = "/org/freedesktop/UDisks2/block_devices/data";
    auto entry = [](const QString& name, const QList<QByteArray>& points, bool ignore = false) {
        return VolumeInterfaces{
            {"org.freedesktop.UDisks2.Block", {{"IdUsage", "filesystem"}, {"IdType", "ntfs"},
                {"IdLabel", name}, {"PreferredDevice", QByteArray("/dev/test\0", 10)},
                {"HintIgnore", ignore}, {"Drive", QVariant::fromValue(QDBusObjectPath("/"))}}},
            {"org.freedesktop.UDisks2.Filesystem", {{"MountPoints", QVariant::fromValue(points)}}}};
    };
    disks.objects.insert(QDBusObjectPath(device), entry("Windows 11", {}));
    disks.objects.insert(QDBusObjectPath(device + "_root"), entry("System", {QByteArray("/\0", 2)}));
    auto efi = entry("EFI", {});
    efi.insert("org.freedesktop.UDisks2.Partition", {{"Type", "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"}});
    disks.objects.insert(QDBusObjectPath(device + "_efi"), efi);
    disks.objects.insert(QDBusObjectPath(device + "_ignored"), entry("Hidden", {}, true));
    require(bus.registerService("org.freedesktop.UDisks2"), "Cannot own fake UDisks service");
    require(bus.registerObject("/org/freedesktop/UDisks2", &disks,
        QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals), "Cannot export volume list");
    require(bus.registerObject(device, &mount, QDBusConnection::ExportAllSlots), "Cannot export fake Mount");
    volumes.refresh();
    auto hasName = [&](const QString& name) {
        return std::ranges::any_of(volumes.volumes(), [&](const QVariant& v) {
            return v.toMap().value("name").toString() == name;
        });
    };
    until([&] { return hasName("Windows 11"); });
    require(!hasName("System") && !hasName("EFI") && !hasName("Hidden"), "System or ignored volumes shown");
    require(mount.calls == 0, "Listing mounted a disk");
    std::cout << "PASS: listing excludes system/EFI/ignored partitions and never mounts\n" << std::flush;
    QString opened, failure;
    QObject::connect(&volumes, &FileVolumes::opened, &volumes, [&](const QString& path) { opened = path; });
    QObject::connect(&volumes, &FileVolumes::failed, &volumes, [&](const QString& error) {
        failure = error;
    });
    volumes.openVolume("invalid");
    require(mount.calls == 0 && volumes.busyId().isEmpty(), "Invalid volume was opened");
    volumes.openVolume(device);
    volumes.openVolume(device);
    require(volumes.busyId() == device, "Mount does not expose busy state");
    until([&] { return opened == directory.path(); });
    require(mount.calls == 1 && volumes.busyId().isEmpty(), "Duplicate mount or stuck busy state");
    std::cout << "PASS: mount runs once asynchronously and opens its returned directory\n" << std::flush;
    mount.deny = true;
    volumes.openVolume(device);
    until([&] { return !failure.isEmpty(); });
    require(failure.contains("permission denied") && volumes.busyId().isEmpty(), "Mount failure lost or dialog stuck");
    std::cout << "PASS: mount failure is reported and clears busy state\n" << std::flush;
    const auto mounted = entry("USB files", {directory.path().toUtf8() + '\0'});
    disks.objects.insert(QDBusObjectPath(device + "_usb"), mounted);
    emit disks.InterfacesAdded(QDBusObjectPath(device + "_usb"), mounted);
    until([&] { return hasName("USB files"); });
    opened.clear();
    volumes.openVolume(device + "_usb");
    require(opened == directory.path() && mount.calls == 2, "Mounted volume remounted or path not decoded");
    bus.unregisterObject(device);
    bus.unregisterObject("/org/freedesktop/UDisks2");
    bus.unregisterService("org.freedesktop.UDisks2");
    std::cout << "PASS: disk discovery, system/EFI filtering, explicit asynchronous mount, failures and hotplug\n";
}

static void checkFileSorting() {
    using namespace hyprstack::models;
    QTemporaryDir directory;
    require(directory.isValid(), "Cannot create sort fixture");
    QDir dir(directory.path());
    require(dir.mkdir("folderA") && dir.mkdir("folderB"), "Cannot create sort folders");
    auto write = [&](const QString& name, int size, qint64 time) {
        QFile file(dir.filePath(name));
        require(file.open(QIODevice::WriteOnly), "Cannot write sort fixture");
        require(file.write(QByteArray(size, 'x')) == size, "Cannot size sort fixture");
        require(file.flush(), "Cannot flush sort fixture");
        require(file.setFileTime(QDateTime::fromSecsSinceEpoch(1600000000 + time),
            QFileDevice::FileModificationTime), "Cannot date sort fixture");
    };
    write("a.bin", 90, 300);
    write("b.txt", 10, 100);
    write("c.bin", 50, 200);
    FileSystemModel model;
    model.setWatchChanges(false);
    model.setPath(directory.path());
    until([&] { return model.rowCount() == 5; });
    auto entry = [&](int row) { return model.data(model.index(row, 0), Qt::UserRole).value<FileSystemEntry*>(); };
    auto files = [&] {
        require(entry(0)->isDir() && entry(1)->isDir(), "Descending order moved folders below files");
        QStringList result;
        for (int row = 2; row < model.rowCount(); ++row) result.append(entry(row)->name());
        return result;
    };
    require(files() == QStringList{"a.bin", "b.txt", "c.bin"}, "Name sort failed");
    QPersistentModelIndex selected(model.index(3, 0));
    auto* selectedFile = entry(3);
    model.setSortBy(FileSystemModel::SortBy::Size);
    require(files() == QStringList{"b.txt", "c.bin", "a.bin"}, "Size sort failed");
    require(selected.row() == 2 && selected.data(Qt::UserRole).value<FileSystemEntry*>() == selectedFile,
        "Sorting changed the selected file identity");
    model.setSortBy(FileSystemModel::SortBy::Modified);
    require(files() == QStringList{"b.txt", "c.bin", "a.bin"}, "Modified-date sort failed");
    model.setSortReverse(true);
    require(files() == QStringList{"a.bin", "c.bin", "b.txt"}, "Reverse modified-date sort failed");
    model.setSortBy(FileSystemModel::SortBy::Type);
    model.setSortReverse(false);
    require(files() == QStringList{"a.bin", "c.bin", "b.txt"}, "Type sort failed");
    model.setSortBy(FileSystemModel::SortBy::Size);
    model.setSortReverse(true);
    write("d.txt", 30, 50);
    model.refresh();
    until([&] { return model.rowCount() == 6; });
    require(files() == QStringList{"a.bin", "c.bin", "d.txt", "b.txt"}, "New file inserted at the wrong sorted position");
    write("b.txt", 120, 400);
    model.refresh();
    require(files() == QStringList{"b.txt", "a.bin", "c.bin", "d.txt"}, "Refresh left stale file sizes");
    require(selected.row() == 2 && selectedFile->modified() == QDateTime::fromSecsSinceEpoch(1600000400),
        "Refresh lost the persistent selection or modification time");
    std::cout << "PASS: file sorting by name/date/size/type, reverse order, folders first, persistent selection and refreshed metadata\n";
}

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
        checkVolumes();
        checkFileSorting();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
#include "portal_contracts.moc"
