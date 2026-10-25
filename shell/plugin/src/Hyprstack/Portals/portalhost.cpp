#include "portalhost.hpp"

#include <qdbusconnection.h>
#include <qdbuserror.h>
#include <qloggingcategory.h>
#include <qstringlist.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcPortalHost, "hyprstack.portals.host", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_serviceName = u"org.freedesktop.impl.portal.desktop.hyprstack"_s;
const QString k_objectPath = u"/org/freedesktop/portal/desktop"_s;

} // namespace

PortalHost::PortalHost(QObject* parent) : QObject(parent) {}

PortalHost::~PortalHost() {
    if (!m_registered)
        return;

    auto bus = QDBusConnection::sessionBus();
    bus.unregisterService(k_serviceName);
    bus.unregisterObject(k_objectPath);
}

QQmlListProperty<Portal> PortalHost::portals() {
    return { this, this, &PortalHost::appendPortal, &PortalHost::portalCount, &PortalHost::portalAt,
        &PortalHost::clearPortals };
}

bool PortalHost::registered() const {
    return m_registered;
}

QString PortalHost::serviceName() {
    return k_serviceName;
}

QStringList PortalHost::interfaces() const {
    QStringList names;
    names.reserve(m_portals.size());
    for (const auto* portal : m_portals)
        names.append(portal->interfaceName());
    return names;
}

void PortalHost::classBegin() {}

void PortalHost::componentComplete() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCWarning(lcPortalHost) << "No session bus, portals unavailable:" << bus.lastError().message();
        return;
    }

    for (auto* portal : std::as_const(m_portals))
        portal->exportOn(&m_exported);

    if (!bus.registerObject(k_objectPath, &m_exported, QDBusConnection::ExportAdaptors)) {
        qCWarning(lcPortalHost) << "Failed to export" << k_objectPath << ":" << bus.lastError().message();
        return;
    }

    // Losing the race against another backend is not fatal: the shell keeps
    // running and the desktop portal falls back to whoever owns the name.
    if (!bus.registerService(k_serviceName)) {
        qCWarning(lcPortalHost) << "Another backend already owns" << k_serviceName << ":"
                                << bus.lastError().message();
        bus.unregisterObject(k_objectPath);
        return;
    }

    m_registered = true;
    emit registeredChanged();
    qCInfo(lcPortalHost) << "Serving" << interfaces().join(u", "_s) << "as" << k_serviceName;
}

void PortalHost::appendPortal(QQmlListProperty<Portal>* list, Portal* portal) {
    auto* self = static_cast<PortalHost*>(list->object);
    if (self->m_registered) {
        qCWarning(lcPortalHost) << "Ignoring" << portal->interfaceName() << "added after registration";
        return;
    }
    self->m_portals.append(portal);
}

qsizetype PortalHost::portalCount(QQmlListProperty<Portal>* list) {
    return static_cast<PortalHost*>(list->object)->m_portals.size();
}

Portal* PortalHost::portalAt(QQmlListProperty<Portal>* list, qsizetype index) {
    return static_cast<PortalHost*>(list->object)->m_portals.at(index);
}

void PortalHost::clearPortals(QQmlListProperty<Portal>* list) {
    static_cast<PortalHost*>(list->object)->m_portals.clear();
}

} // namespace hyprstack::portals
