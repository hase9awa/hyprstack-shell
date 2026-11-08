#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>

namespace hyprstack::portals {

// One org.freedesktop.impl.portal.* interface. Every portal declared inside a
// host shares the single object path the desktop portal looks them up on.
class Portal : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Declare one of the portal implementations instead")

public:
    explicit Portal(QObject* parent = nullptr) : QObject(parent) {}

    // Attaches the adaptor carrying this interface to the exported object.
    virtual void exportOn(QObject* target) = 0;
    [[nodiscard]] virtual QString interfaceName() const = 0;
};

} // namespace hyprstack::portals
