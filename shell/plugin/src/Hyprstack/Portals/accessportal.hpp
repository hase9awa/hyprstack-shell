#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusargument.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qmetatype.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qstring.h>
#include <qvariant.h>

#include "portal.hpp"
#include "portalrequest.hpp"

namespace hyprstack::portals {

// One option of a choice, and also one answer to it: the dialog sends back a
// pair of this shape for every choice it was given.
struct AccessOption {
    QString id;
    QString label;
};

// An extra question the dialog asks alongside the permission itself. An empty
// option list means a plain checkbox, answered with "true" or "false".
struct AccessChoice {
    QString id;
    QString label;
    QList<AccessOption> options;
    QString selected;
};

QDBusArgument& operator<<(QDBusArgument& argument, const AccessOption& option);
const QDBusArgument& operator>>(const QDBusArgument& argument, AccessOption& option);
QDBusArgument& operator<<(QDBusArgument& argument, const AccessChoice& choice);
const QDBusArgument& operator>>(const QDBusArgument& argument, AccessChoice& choice);

// One permission an application is waiting on. The shell asks the user and
// answers through grant() or deny().
class AccessRequest : public PortalRequest {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the access portal")

    Q_PROPERTY(QString subtitle READ subtitle CONSTANT)
    Q_PROPERTY(QString body READ body CONSTANT)
    Q_PROPERTY(QString icon READ icon CONSTANT)
    Q_PROPERTY(QString grantLabel READ grantLabel CONSTANT)
    Q_PROPERTY(QString denyLabel READ denyLabel CONSTANT)
    // Each entry is {id, label, options, selected}, where an option is
    // {id, label} and an empty option list asks for a plain yes or no.
    Q_PROPERTY(QVariantList choices READ choices CONSTANT)

public:
    AccessRequest(QString appId, QString title, QString subtitle, QString body, QVariantMap options, QDBusMessage call,
        QDBusObjectPath handle, QObject* parent = nullptr);

    [[nodiscard]] QString subtitle() const;
    [[nodiscard]] QString body() const;
    [[nodiscard]] QString icon() const;
    [[nodiscard]] QString grantLabel() const;
    [[nodiscard]] QString denyLabel() const;
    [[nodiscard]] QVariantList choices() const;

    // Selections map a choice id onto the option id it was answered with;
    // whatever the dialog leaves out keeps the default the request came with.
    Q_INVOKABLE void grant(const QVariantMap& selections = {});
    Q_INVOKABLE void deny();

private:
    QString m_subtitle;
    QString m_body;
    QList<AccessChoice> m_choices;
};

// org.freedesktop.impl.portal.Access. The permission prompt behind the camera,
// location and background portals, asked on behalf of the desktop portal.
class AccessPortal : public Portal {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQmlListProperty<hyprstack::portals::AccessRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit AccessPortal(QObject* parent = nullptr);

    void exportOn(QObject* target) override;
    [[nodiscard]] QString interfaceName() const override;

    [[nodiscard]] QQmlListProperty<AccessRequest> requests();

    void add(const QDBusObjectPath& handle, const QString& appId, const QString& title, const QString& subtitle,
        const QString& body, const QVariantMap& options, const QDBusMessage& call);

signals:
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<AccessRequest>* list);
    static AccessRequest* requestAt(QQmlListProperty<AccessRequest>* list, qsizetype index);

    QList<AccessRequest*> m_requests;
};

class AccessAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Access")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.Access\">\n"
        "    <property name=\"version\" type=\"u\" access=\"read\"/>\n"
        "    <method name=\"AccessDialog\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"subtitle\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"body\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "      <arg name=\"results\" type=\"a{sv}\" direction=\"out\"/>\n"
        "    </method>\n"
        "  </interface>\n")

    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit AccessAdaptor(AccessPortal* portal, QObject* parent);

    [[nodiscard]] static uint version();

    // NOLINTNEXTLINE(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void AccessDialog(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QString& title, const QString& subtitle, const QString& body, const QVariantMap& options,
        const QDBusMessage& message);

private:
    AccessPortal* m_portal;
};

} // namespace hyprstack::portals

Q_DECLARE_METATYPE(hyprstack::portals::AccessOption)
Q_DECLARE_METATYPE(hyprstack::portals::AccessChoice)
