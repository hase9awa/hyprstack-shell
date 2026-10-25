#include "portalrequest.hpp"

#include <qdbusconnection.h>
#include <qloggingcategory.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcPortalRequest, "hyprstack.portals.request", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

PortalRequest::PortalRequest(QString appId, QString title, QVariantMap options, QDBusMessage call,
    QDBusObjectPath handle, QObject* parent)
    : QObject(parent)
    , m_appId(std::move(appId))
    , m_title(std::move(title))
    , m_options(std::move(options))
    , m_call(std::move(call))
    , m_handle(std::move(handle)) {}

QString PortalRequest::appId() const {
    return m_appId;
}

QString PortalRequest::title() const {
    return m_title;
}

bool PortalRequest::answered() const {
    return m_answered;
}

QDBusObjectPath PortalRequest::handle() const {
    return m_handle;
}

void PortalRequest::exportHandle() {
    new RequestAdaptor(this); // NOLINT(cppcoreguidelines-owning-memory) parented to the request

    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(m_handle.path(), this, QDBusConnection::ExportAdaptors))
        qCWarning(lcPortalRequest) << "Failed to export request handle" << m_handle.path();
}

void PortalRequest::close() {
    qCDebug(lcPortalRequest) << "Request withdrawn by" << m_appId;
    respond(Other);
}

QVariant PortalRequest::option(const QString& name) const {
    return m_options.value(name);
}

QString PortalRequest::label(const QString& name) const {
    return m_options.value(name).toString().remove(u'_');
}

void PortalRequest::respond(Response response, const QVariantMap& results) {
    if (m_answered)
        return;

    m_answered = true;
    emit answeredChanged();

    auto bus = QDBusConnection::sessionBus();
    bus.send(m_call.createReply({ QVariant::fromValue(static_cast<uint>(response)), QVariant::fromValue(results) }));
    bus.unregisterObject(m_handle.path());

    // The dialog that answered is the one listening for this: retire the
    // request once its handler has returned rather than underneath it.
    QMetaObject::invokeMethod(
        this,
        [this] {
            emit finished();
            deleteLater();
        },
        Qt::QueuedConnection);
}

RequestAdaptor::RequestAdaptor(PortalRequest* request) : QDBusAbstractAdaptor(request), m_request(request) {}

void RequestAdaptor::Close() {
    m_request->close();
}

} // namespace hyprstack::portals
