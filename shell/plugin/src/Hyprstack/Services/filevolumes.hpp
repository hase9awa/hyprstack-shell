#pragma once

#include <qdbusextratypes.h>
#include <qmap.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qtimer.h>
#include <qvariant.h>

namespace hyprstack::services {

using VolumeInterfaces = QMap<QString, QVariantMap>;
using VolumeObjects = QMap<QDBusObjectPath, VolumeInterfaces>;

// Created only while a file dialog is open. Listing never mounts a device;
// Mount is requested through UDisks/Polkit only after an explicit click.
class FileVolumes : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantList volumes READ volumes NOTIFY volumesChanged)
    Q_PROPERTY(QString busyId READ busyId NOTIFY busyIdChanged)

public:
    explicit FileVolumes(QObject* parent = nullptr);
    [[nodiscard]] QVariantList volumes() const { return m_volumes; }
    [[nodiscard]] QString busyId() const { return m_busyId; }
    Q_INVOKABLE void openVolume(const QString& id);

public slots:
    void refresh();

signals:
    void volumesChanged();
    void busyIdChanged();
    void opened(const QString& path);
    void failed(const QString& message);

private:
    void load();
    [[nodiscard]] static QVariantList collectVolumes(const VolumeObjects& objects);
    QVariantList m_volumes;
    QString m_busyId;
    QTimer m_refresh;
    bool m_loading = false;
    bool m_reload = false;
};

} // namespace hyprstack::services

Q_DECLARE_METATYPE(hyprstack::services::VolumeObjects)
