#include "wallpaperportal.hpp"

#include <qloggingcategory.h>
#include <qurl.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcWallpaper, "hyprstack.portals.wallpaper", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_interface = u"org.freedesktop.impl.portal.Wallpaper"_s;

constexpr uint k_version = 1;

} // namespace

WallpaperRequest::WallpaperRequest(QString appId, QString uri, QVariantMap options, QDBusMessage call,
    QDBusObjectPath handle, QObject* parent)
    : PortalRequest(std::move(appId), {}, std::move(options), std::move(call), std::move(handle), parent)
    , m_uri(std::move(uri)) {}

QString WallpaperRequest::uri() const {
    return m_uri;
}

QString WallpaperRequest::path() const {
    const auto url = QUrl(m_uri);
    return url.isLocalFile() ? url.toLocalFile() : QString();
}

bool WallpaperRequest::showPreview() const {
    return option(u"show-preview"_s).toBool();
}

WallpaperRequest::Target WallpaperRequest::target() const {
    const auto where = option(u"set-on"_s).toString();
    if (where == u"lockscreen"_s)
        return Target::Lockscreen;
    if (where == u"both"_s)
        return Target::Both;
    return Target::Background;
}

void WallpaperRequest::accept() {
    respondBare(Success);
}

void WallpaperRequest::reject() {
    respondBare(Cancelled);
}

WallpaperPortal::WallpaperPortal(QObject* parent) : Portal(parent) {}

void WallpaperPortal::exportOn(QObject* target) {
    new WallpaperAdaptor(this, target); // NOLINT(cppcoreguidelines-owning-memory) parented to target
}

QString WallpaperPortal::interfaceName() const {
    return k_interface;
}

QQmlListProperty<WallpaperRequest> WallpaperPortal::requests() {
    return { this, this, &WallpaperPortal::requestCount, &WallpaperPortal::requestAt };
}

void WallpaperPortal::add(const QDBusObjectPath& handle, const QString& appId, const QString& uri,
    const QVariantMap& options, const QDBusMessage& call) {
    call.setDelayedReply(true);

    auto* request = new WallpaperRequest(appId, uri, options, call, handle, this);
    request->exportHandle();

    connect(request, &PortalRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcWallpaper) << "Background offered by" << (appId.isEmpty() ? u"an application"_s : appId);
}

qsizetype WallpaperPortal::requestCount(QQmlListProperty<WallpaperRequest>* list) {
    return static_cast<WallpaperPortal*>(list->object)->m_requests.size();
}

WallpaperRequest* WallpaperPortal::requestAt(QQmlListProperty<WallpaperRequest>* list, qsizetype index) {
    return static_cast<WallpaperPortal*>(list->object)->m_requests.at(index);
}

WallpaperAdaptor::WallpaperAdaptor(WallpaperPortal* portal, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_portal(portal) {}

uint WallpaperAdaptor::version() {
    return k_version;
}

void WallpaperAdaptor::SetWallpaperURI(const QDBusObjectPath& handle, const QString& appId,
    const QString& parentWindow, const QString& uri, const QVariantMap& options, const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(handle, appId, uri, options, message);
}

} // namespace hyprstack::portals
