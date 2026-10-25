#pragma once

#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qqmlparserstatus.h>
#include <qstring.h>

#include "portal.hpp"

namespace hyprstack::portals {

// Owns the backend's bus name and the object its interfaces are exported on.
// The desktop portal finds a backend by that name, so a session has room for
// exactly one host.
class PortalHost : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_CLASSINFO("DefaultProperty", "portals")

    Q_PROPERTY(QQmlListProperty<hyprstack::portals::Portal> portals READ portals CONSTANT)
    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)
    Q_PROPERTY(QString serviceName READ serviceName CONSTANT)
    Q_PROPERTY(QStringList interfaces READ interfaces NOTIFY registeredChanged)

public:
    explicit PortalHost(QObject* parent = nullptr);
    ~PortalHost() override;
    Q_DISABLE_COPY_MOVE(PortalHost)

    [[nodiscard]] QQmlListProperty<Portal> portals();
    [[nodiscard]] bool registered() const;
    [[nodiscard]] static QString serviceName();
    [[nodiscard]] QStringList interfaces() const;

    void classBegin() override;
    void componentComplete() override;

signals:
    void registeredChanged();

private:
    static void appendPortal(QQmlListProperty<Portal>* list, Portal* portal);
    static qsizetype portalCount(QQmlListProperty<Portal>* list);
    static Portal* portalAt(QQmlListProperty<Portal>* list, qsizetype index);
    static void clearPortals(QQmlListProperty<Portal>* list);

    // Carries the adaptors instead of the host itself: the host is a QML
    // element with properties that have no business on the bus.
    QObject m_exported;
    QList<Portal*> m_portals;
    bool m_registered = false;
};

} // namespace hyprstack::portals
