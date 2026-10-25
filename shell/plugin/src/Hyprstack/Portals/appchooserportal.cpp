#include "appchooserportal.hpp"

#include <qloggingcategory.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcAppChooser, "hyprstack.portals.appchooser", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_interface = u"org.freedesktop.impl.portal.AppChooser"_s;

constexpr uint k_version = 2;

} // namespace

AppChooserRequest::AppChooserRequest(QString appId, QStringList choices, QVariantMap options, QDBusMessage call,
    QDBusObjectPath handle, QObject* parent)
    : PortalRequest(std::move(appId), {}, std::move(options), std::move(call), std::move(handle), parent)
    , m_choices(std::move(choices)) {}

QStringList AppChooserRequest::choices() const {
    return m_choices;
}

QString AppChooserRequest::lastChoice() const {
    return option(u"last_choice"_s).toString();
}

QString AppChooserRequest::contentType() const {
    return option(u"content_type"_s).toString();
}

QString AppChooserRequest::uri() const {
    return option(u"uri"_s).toString();
}

QString AppChooserRequest::fileName() const {
    return option(u"filename"_s).toString();
}

void AppChooserRequest::setChoices(const QStringList& choices) {
    if (m_choices == choices)
        return;

    m_choices = choices;
    emit choicesChanged();
}

void AppChooserRequest::choose(const QString& id) {
    if (id.isEmpty()) {
        reject();
        return;
    }

    QVariantMap results { { u"choice"_s, id } };

    // The shell has no way to mint a Wayland activation token, so the
    // caller's own one is handed back; the interface allows reusing it.
    const auto token = option(u"activation_token"_s).toString();
    if (!token.isEmpty())
        results.insert(u"activation_token"_s, token);

    respond(Success, results);
}

void AppChooserRequest::reject() {
    respond(Cancelled);
}

AppChooserPortal::AppChooserPortal(QObject* parent) : Portal(parent) {}

void AppChooserPortal::exportOn(QObject* target) {
    new AppChooserAdaptor(this, target); // NOLINT(cppcoreguidelines-owning-memory) parented to target
}

QString AppChooserPortal::interfaceName() const {
    return k_interface;
}

QQmlListProperty<AppChooserRequest> AppChooserPortal::requests() {
    return { this, this, &AppChooserPortal::requestCount, &AppChooserPortal::requestAt };
}

void AppChooserPortal::add(const QDBusObjectPath& handle, const QString& appId, const QStringList& choices,
    const QVariantMap& options, const QDBusMessage& call) {
    call.setDelayedReply(true);

    auto* request = new AppChooserRequest(appId, choices, options, call, handle, this);
    request->exportHandle();

    connect(request, &PortalRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcAppChooser) << "Chooser requested by" << (appId.isEmpty() ? u"an application"_s : appId) << "with"
                         << choices.size() << "candidates";
}

void AppChooserPortal::update(const QDBusObjectPath& handle, const QStringList& choices) {
    for (auto* request : std::as_const(m_requests)) {
        if (request->handle() == handle) {
            request->setChoices(choices);
            return;
        }
    }

    qCDebug(lcAppChooser) << "No open chooser at" << handle.path();
}

qsizetype AppChooserPortal::requestCount(QQmlListProperty<AppChooserRequest>* list) {
    return static_cast<AppChooserPortal*>(list->object)->m_requests.size();
}

AppChooserRequest* AppChooserPortal::requestAt(QQmlListProperty<AppChooserRequest>* list, qsizetype index) {
    return static_cast<AppChooserPortal*>(list->object)->m_requests.at(index);
}

AppChooserAdaptor::AppChooserAdaptor(AppChooserPortal* portal, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_portal(portal) {}

uint AppChooserAdaptor::version() {
    return k_version;
}

void AppChooserAdaptor::ChooseApplication(const QDBusObjectPath& handle, const QString& appId,
    const QString& parentWindow, const QStringList& choices, const QVariantMap& options, const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(handle, appId, choices, options, message);
}

void AppChooserAdaptor::UpdateChoices(const QDBusObjectPath& handle, const QStringList& choices) {
    m_portal->update(handle, choices);
}

} // namespace hyprstack::portals
