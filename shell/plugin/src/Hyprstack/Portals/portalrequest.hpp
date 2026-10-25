#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qvariant.h>

namespace hyprstack::portals {

// One call an application is waiting on. The shell shows a dialog for it and
// answers through the portal that created it; the request then replies to the
// pending call and retires itself.
class PortalRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the portal implementations")

    Q_PROPERTY(QString appId READ appId CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(bool modal READ modal CONSTANT)
    Q_PROPERTY(bool answered READ answered NOTIFY answeredChanged)

public:
    PortalRequest(QString appId, QString title, QVariantMap options, QDBusMessage call, QDBusObjectPath handle,
        QObject* parent = nullptr);

    [[nodiscard]] QString appId() const;
    [[nodiscard]] QString title() const;
    [[nodiscard]] bool modal() const;
    [[nodiscard]] bool answered() const;
    [[nodiscard]] QDBusObjectPath handle() const;

    // Exports the handle the caller chose, which it owns and may withdraw the
    // dialog through. The reply itself must already be delayed by then.
    void exportHandle();

    // The application withdrew the request before the user answered.
    void close();

signals:
    void answeredChanged();
    void finished();

protected:
    // The codes org.freedesktop.impl.portal.Request answers with.
    enum Response : quint8 {
        Success = 0,
        Cancelled = 1,
        Other = 2,
    };

    [[nodiscard]] QVariant option(const QString& name) const;
    // Toolkits mark the accelerator with an underscore the shell does not use.
    [[nodiscard]] QString label(const QString& name) const;

    void respond(Response response, const QVariantMap& results = {});

private:
    QString m_appId;
    QString m_title;
    QVariantMap m_options;
    QDBusMessage m_call;
    QDBusObjectPath m_handle;
    bool m_answered = false;
};

// org.freedesktop.impl.portal.Request, exported on the handle the caller
// chose so it can withdraw a dialog it no longer needs.
class RequestAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.Request\">\n"
        "    <method name=\"Close\"/>\n"
        "  </interface>\n")

public:
    explicit RequestAdaptor(PortalRequest* request);

    // NOLINTNEXTLINE(readability-identifier-naming) D-Bus spells it this way
public slots:
    void Close();

private:
    PortalRequest* m_request;
};

} // namespace hyprstack::portals
