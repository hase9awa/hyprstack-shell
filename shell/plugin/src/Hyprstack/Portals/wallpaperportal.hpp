#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qstring.h>
#include <qvariant.h>

#include "portal.hpp"
#include "portalrequest.hpp"

namespace hyprstack::portals {

// One picture an application is offering as the background. The shell either
// sets it outright or shows it first, depending on what was asked.
class WallpaperRequest : public PortalRequest {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the wallpaper portal")

    Q_PROPERTY(QString uri READ uri CONSTANT)
    // The picture as a local file, empty when it lives somewhere the shell
    // cannot read from.
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(bool showPreview READ showPreview CONSTANT)
    Q_PROPERTY(Target target READ target CONSTANT)

public:
    enum class Target : quint8 {
        Background,
        Lockscreen,
        Both,
    };
    Q_ENUM(Target)

    WallpaperRequest(QString appId, QString uri, QVariantMap options, QDBusMessage call, QDBusObjectPath handle,
        QObject* parent = nullptr);

    [[nodiscard]] QString uri() const;
    [[nodiscard]] QString path() const;
    [[nodiscard]] bool showPreview() const;
    [[nodiscard]] Target target() const;

    Q_INVOKABLE void accept();
    Q_INVOKABLE void reject();

private:
    QString m_uri;
};

// org.freedesktop.impl.portal.Wallpaper. Applications that want to hand the
// desktop a new background go through here rather than writing the setting.
class WallpaperPortal : public Portal {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQmlListProperty<hyprstack::portals::WallpaperRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit WallpaperPortal(QObject* parent = nullptr);

    void exportOn(QObject* target) override;
    [[nodiscard]] QString interfaceName() const override;

    [[nodiscard]] QQmlListProperty<WallpaperRequest> requests();

    void add(const QDBusObjectPath& handle, const QString& appId, const QString& uri, const QVariantMap& options,
        const QDBusMessage& call);

signals:
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<WallpaperRequest>* list);
    static WallpaperRequest* requestAt(QQmlListProperty<WallpaperRequest>* list, qsizetype index);

    QList<WallpaperRequest*> m_requests;
};

class WallpaperAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Wallpaper")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.Wallpaper\">\n"
        "    <property name=\"version\" type=\"u\" access=\"read\"/>\n"
        "    <method name=\"SetWallpaperURI\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"uri\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "    </method>\n"
        "  </interface>\n")

    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit WallpaperAdaptor(WallpaperPortal* portal, QObject* parent);

    [[nodiscard]] static uint version();

    // NOLINTNEXTLINE(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void SetWallpaperURI(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QString& uri, const QVariantMap& options, const QDBusMessage& message);

private:
    WallpaperPortal* m_portal;
};

} // namespace hyprstack::portals
