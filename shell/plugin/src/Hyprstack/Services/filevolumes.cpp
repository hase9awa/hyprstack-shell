#include "filevolumes.hpp"

#include <qdbusargument.h>
#include <qdbusconnection.h>
#include <qdbusmetatype.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusservicewatcher.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qlocale.h>
#include <qset.h>
#include <qstorageinfo.h>
#include <qtconcurrentrun.h>

#include <algorithm>
#include <utility>

namespace hyprstack::services {
using Qt::StringLiterals::operator""_s;

namespace {
const QString service = u"org.freedesktop.UDisks2"_s;
const QString manager = u"/org/freedesktop/UDisks2"_s;
const QString blockInterface = u"org.freedesktop.UDisks2.Block"_s;
const QString filesystemInterface = u"org.freedesktop.UDisks2.Filesystem"_s;

QString bytesString(QByteArray bytes) {
    const auto zero = bytes.indexOf('\0');
    if (zero >= 0)
        bytes.truncate(zero);
    return QString::fromUtf8(bytes);
}

QString devicePath(const QByteArray& bytes) {
    const auto raw = bytesString(bytes);
    const auto path = raw.startsWith(u"/dev/") ? raw.section(u'[', 0, 0) : raw;
    const auto canonical = path.startsWith(u"/dev/") ? QFileInfo(path).canonicalFilePath() : QString{};
    return canonical.isEmpty() ? path : canonical;
}

bool systemMount(const QString& path) {
    return path == u"/" || path == u"/boot" || path.startsWith(u"/boot/")
        || path == u"/efi" || path.startsWith(u"/efi/");
}
} // namespace

FileVolumes::FileVolumes(QObject* parent) : QObject(parent) {
    qDBusRegisterMetaType<VolumeInterfaces>();
    qDBusRegisterMetaType<VolumeObjects>();
    qDBusRegisterMetaType<QList<QByteArray>>();
    m_refresh.setSingleShot(true);
    m_refresh.setInterval(80);
    connect(&m_refresh, &QTimer::timeout, this, &FileVolumes::load);
    auto bus = QDBusConnection::systemBus();
    bus.connect(service, manager, u"org.freedesktop.DBus.ObjectManager"_s,
        u"InterfacesAdded"_s, this, SLOT(refresh()));
    bus.connect(service, manager, u"org.freedesktop.DBus.ObjectManager"_s,
        u"InterfacesRemoved"_s, this, SLOT(refresh()));
    bus.connect(service, {}, u"org.freedesktop.DBus.Properties"_s,
        u"PropertiesChanged"_s, this, SLOT(refresh()));
    auto* watcher = new QDBusServiceWatcher(service, bus,
        QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &FileVolumes::refresh);
    refresh();
}

void FileVolumes::refresh() {
    m_refresh.start();
}

void FileVolumes::load() {
    if (m_loading) {
        m_reload = true;
        return;
    }
    m_loading = true;
    auto message = QDBusMessage::createMethodCall(service, manager,
        u"org.freedesktop.DBus.ObjectManager"_s, u"GetManagedObjects"_s);
    auto* call = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this, call] {
        const QDBusPendingReply<VolumeObjects> reply = *call;
        const auto objects = reply.isError() ? VolumeObjects{} : reply.value();
        call->deleteLater();
        // statfs on an unavailable network mount must not stop shell input.
        QtConcurrent::run([objects] { return collectVolumes(objects); }).then(this, [this](QVariantList volumes) {
            if (m_volumes != volumes) {
                m_volumes = std::move(volumes);
                emit volumesChanged();
            }
            m_loading = false;
            if (m_reload) {
                m_reload = false;
                refresh();
            }
        });
    });
}

QVariantList FileVolumes::collectVolumes(const VolumeObjects& objects) {
    QVariantList volumes;
    QSet<QString> devices, mounts;
    for (auto it = objects.cbegin(); it != objects.cend(); ++it) {
        const auto& interfaces = it.value();
        const auto block = interfaces.value(blockInterface);
        if (!interfaces.contains(filesystemInterface) || block.value(u"HintIgnore"_s).toBool()
            || block.value(u"IdUsage"_s).toString() != u"filesystem")
            continue;
        const auto device = devicePath(block.value(u"PreferredDevice"_s,
            block.value(u"Device"_s)).toByteArray());
        devices.insert(device);
        const auto points = qdbus_cast<QList<QByteArray>>(
            interfaces.value(filesystemInterface).value(u"MountPoints"_s));
        QString path;
        bool system = false;
        for (const auto& point : points) {
            const auto mount = bytesString(point);
            system |= systemMount(mount);
            if (path.isEmpty() && QFileInfo(mount).isDir())
                path = mount;
        }
        const auto partitionType = interfaces.value(u"org.freedesktop.UDisks2.Partition"_s)
            .value(u"Type"_s).toString().toLower();
        // EFI/BIOS partitions are not places for documents. Internal data
        // partitions remain visible even when UDisks marks them HintSystem.
        if (system || partitionType == u"c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
            || partitionType == u"21686148-6449-6e6f-744e-656564454649")
            continue;
        const auto drivePath = qdbus_cast<QDBusObjectPath>(block.value(u"Drive"_s)).path();
        const auto drive = objects.value(QDBusObjectPath(drivePath.isEmpty() ? u"/"_s : drivePath))
            .value(u"org.freedesktop.UDisks2.Drive"_s);
        const auto size = block.value(u"Size"_s).toLongLong();
        auto name = block.value(u"HintName"_s).toString();
        if (name.isEmpty()) name = block.value(u"IdLabel"_s).toString();
        if (name.isEmpty()) name = QLocale().formattedDataSize(size) + u" "_s
            + block.value(u"IdType"_s).toString().toUpper();
        volumes.append(QVariantMap{
            {u"id"_s, it.key().path()}, {u"name"_s, name}, {u"device"_s, device},
            {u"path"_s, path}, {u"mounted"_s, !path.isEmpty()},
            {u"removable"_s, drive.value(u"Removable"_s).toBool()
                || drive.value(u"ConnectionBus"_s).toString() == u"usb"}});
        if (!path.isEmpty()) mounts.insert(path);
    }
    // Also offer mounted filesystems without a UDisks block object (network
    // shares, FUSE, and systems where UDisks is not installed).
    devices.insert(devicePath(QStorageInfo::root().device()));
    for (const auto& storage : QStorageInfo::mountedVolumes()) {
        const auto path = storage.rootPath();
        const auto device = devicePath(storage.device());
        if (systemMount(path)) {
            devices.insert(device);
            continue;
        }
        if (!storage.isValid() || !storage.isReady()
            || mounts.contains(path) || devices.contains(device))
            continue;
        if (!device.startsWith(u"/dev/") && !path.startsWith(u"/mnt/")
            && !path.startsWith(u"/media/") && !path.startsWith(u"/run/media/"))
            continue;
        volumes.append(QVariantMap{{u"id"_s, path}, {u"name"_s, storage.displayName()},
            {u"device"_s, device}, {u"path"_s, path}, {u"mounted"_s, true}, {u"removable"_s, false}});
        devices.insert(device);
    }
    std::ranges::sort(volumes, [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(u"name"_s).toString().localeAwareCompare(
            b.toMap().value(u"name"_s).toString()) < 0;
    });
    return volumes;
}

void FileVolumes::openVolume(const QString& id) {
    if (!m_busyId.isEmpty()) return;
    const auto it = std::ranges::find_if(m_volumes, [&id](const QVariant& volume) {
        return volume.toMap().value(u"id"_s).toString() == id;
    });
    if (it == m_volumes.end()) return;
    const auto volume = it->toMap();
    const auto path = volume.value(u"path"_s).toString();
    if (!path.isEmpty()) {
        emit opened(path);
        return;
    }
    m_busyId = id;
    emit busyIdChanged();
    auto message = QDBusMessage::createMethodCall(service, id, filesystemInterface, u"Mount"_s);
    message.setInteractiveAuthorizationAllowed(true);
    message.setArguments({QVariantMap{}});
    auto* call = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, 120000), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this, call] {
        const QDBusPendingReply<QString> reply = *call;
        m_busyId.clear();
        emit busyIdChanged();
        if (reply.isError()) emit failed(reply.error().message());
        else if (!reply.value().isEmpty()) emit opened(reply.value());
        refresh();
        call->deleteLater();
    });
}
} // namespace hyprstack::services
