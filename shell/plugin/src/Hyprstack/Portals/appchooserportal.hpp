#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include "portal.hpp"
#include "portalrequest.hpp"

namespace hyprstack::portals {

// One "open with" an application is waiting on. The shell offers the choices
// the desktop portal collected and answers through choose() or reject().
class AppChooserRequest : public PortalRequest {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the app chooser portal")

    // Desktop entry ids, in the order the portal offered them. The list can
    // change while the dialog is open, once an application is installed.
    Q_PROPERTY(QStringList choices READ choices NOTIFY choicesChanged)
    Q_PROPERTY(QString lastChoice READ lastChoice CONSTANT)
    Q_PROPERTY(QString contentType READ contentType CONSTANT)
    Q_PROPERTY(QString uri READ uri CONSTANT)
    // A bare file name without its path, as the portal sends it.
    Q_PROPERTY(QString fileName READ fileName CONSTANT)

public:
    AppChooserRequest(QString appId, QStringList choices, QVariantMap options, QDBusMessage call,
        QDBusObjectPath handle, QObject* parent = nullptr);

    [[nodiscard]] QStringList choices() const;
    [[nodiscard]] QString lastChoice() const;
    [[nodiscard]] QString contentType() const;
    [[nodiscard]] QString uri() const;
    [[nodiscard]] QString fileName() const;

    void setChoices(const QStringList& choices);

    // The id has to be one of the offered choices, spelled the way it
    // arrived: the portal hands the same spelling back as last_choice.
    Q_INVOKABLE void choose(const QString& id);
    Q_INVOKABLE void reject();

signals:
    void choicesChanged();

private:
    QStringList m_choices;
};

// org.freedesktop.impl.portal.AppChooser. The "open with" dialog the desktop
// portal shows when a URI has no handler of its own, or several.
class AppChooserPortal : public Portal {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQmlListProperty<hyprstack::portals::AppChooserRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit AppChooserPortal(QObject* parent = nullptr);

    void exportOn(QObject* target) override;
    [[nodiscard]] QString interfaceName() const override;

    [[nodiscard]] QQmlListProperty<AppChooserRequest> requests();

    void add(const QDBusObjectPath& handle, const QString& appId, const QStringList& choices,
        const QVariantMap& options, const QDBusMessage& call);
    void update(const QDBusObjectPath& handle, const QStringList& choices);

signals:
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<AppChooserRequest>* list);
    static AppChooserRequest* requestAt(QQmlListProperty<AppChooserRequest>* list, qsizetype index);

    QList<AppChooserRequest*> m_requests;
};

class AppChooserAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.AppChooser")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.AppChooser\">\n"
        "    <property name=\"version\" type=\"u\" access=\"read\"/>\n"
        "    <method name=\"ChooseApplication\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"choices\" type=\"as\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "      <arg name=\"results\" type=\"a{sv}\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"UpdateChoices\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"choices\" type=\"as\" direction=\"in\"/>\n"
        "    </method>\n"
        "  </interface>\n")

    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit AppChooserAdaptor(AppChooserPortal* portal, QObject* parent);

    [[nodiscard]] static uint version();

    // NOLINTBEGIN(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void ChooseApplication(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QStringList& choices, const QVariantMap& options, const QDBusMessage& message);
    void UpdateChoices(const QDBusObjectPath& handle, const QStringList& choices);
    // NOLINTEND(readability-identifier-naming)

private:
    AppChooserPortal* m_portal;
};

} // namespace hyprstack::portals
