#include "accessportal.hpp"

#include <qdbusmetatype.h>
#include <qloggingcategory.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcAccess, "hyprstack.portals.access", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_interface = u"org.freedesktop.impl.portal.Access"_s;

constexpr uint k_version = 1;

template<typename T>
T demarshal(const QVariant& value) {
    T result;
    if (value.canConvert<QDBusArgument>())
        value.value<QDBusArgument>() >> result;
    return result;
}

} // namespace

QDBusArgument& operator<<(QDBusArgument& argument, const AccessOption& option) {
    argument.beginStructure();
    argument << option.id << option.label;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, AccessOption& option) {
    argument.beginStructure();
    argument >> option.id >> option.label;
    argument.endStructure();
    return argument;
}

QDBusArgument& operator<<(QDBusArgument& argument, const AccessChoice& choice) {
    argument.beginStructure();
    argument << choice.id << choice.label << choice.options << choice.selected;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, AccessChoice& choice) {
    argument.beginStructure();
    argument >> choice.id >> choice.label >> choice.options >> choice.selected;
    argument.endStructure();
    return argument;
}

AccessRequest::AccessRequest(QString appId, QString title, QString subtitle, QString body, QVariantMap options,
    QDBusMessage call, QDBusObjectPath handle, QObject* parent)
    : PortalRequest(std::move(appId), std::move(title), std::move(options), std::move(call), std::move(handle), parent)
    , m_subtitle(std::move(subtitle))
    , m_body(std::move(body))
    , m_choices(demarshal<QList<AccessChoice>>(option(u"choices"_s))) {}

QString AccessRequest::subtitle() const {
    return m_subtitle;
}

QString AccessRequest::body() const {
    return m_body;
}

QString AccessRequest::icon() const {
    return option(u"icon"_s).toString();
}

QString AccessRequest::grantLabel() const {
    return label(u"grant_label"_s);
}

QString AccessRequest::denyLabel() const {
    return label(u"deny_label"_s);
}

bool AccessRequest::modal() const {
    // A prompt nobody asked to be modeless still has to be answered.
    const auto value = option(u"modal"_s);
    return !value.isValid() || value.toBool();
}

QVariantList AccessRequest::choices() const {
    QVariantList result;
    result.reserve(m_choices.size());

    for (const auto& choice : m_choices) {
        QVariantList options;
        options.reserve(choice.options.size());
        for (const auto& option : choice.options)
            options.append(QVariantMap { { u"id"_s, option.id }, { u"label"_s, option.label } });

        result.append(QVariantMap {
            { u"id"_s, choice.id },
            { u"label"_s, choice.label },
            { u"options"_s, options },
            { u"selected"_s, choice.selected },
        });
    }

    return result;
}

void AccessRequest::grant(const QVariantMap& selections) {
    QList<AccessOption> answers;
    answers.reserve(m_choices.size());
    for (const auto& choice : m_choices)
        answers.append({ choice.id, selections.value(choice.id, choice.selected).toString() });

    QVariantMap results;
    if (!answers.isEmpty())
        results.insert(u"choices"_s, QVariant::fromValue(answers));

    respond(Success, results);
}

void AccessRequest::deny() {
    respond(Cancelled);
}

AccessPortal::AccessPortal(QObject* parent) : Portal(parent) {
    qDBusRegisterMetaType<AccessOption>();
    qDBusRegisterMetaType<QList<AccessOption>>();
    qDBusRegisterMetaType<AccessChoice>();
    qDBusRegisterMetaType<QList<AccessChoice>>();
}

void AccessPortal::exportOn(QObject* target) {
    new AccessAdaptor(this, target); // NOLINT(cppcoreguidelines-owning-memory) parented to target
}

QString AccessPortal::interfaceName() const {
    return k_interface;
}

QQmlListProperty<AccessRequest> AccessPortal::requests() {
    return { this, this, &AccessPortal::requestCount, &AccessPortal::requestAt };
}

void AccessPortal::add(const QDBusObjectPath& handle, const QString& appId, const QString& title,
    const QString& subtitle, const QString& body, const QVariantMap& options, const QDBusMessage& call) {
    call.setDelayedReply(true);

    auto* request = new AccessRequest(appId, title, subtitle, body, options, call, handle, this);
    request->exportHandle();

    connect(request, &PortalRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcAccess) << "Permission requested by" << (appId.isEmpty() ? u"an application"_s : appId);
}

qsizetype AccessPortal::requestCount(QQmlListProperty<AccessRequest>* list) {
    return static_cast<AccessPortal*>(list->object)->m_requests.size();
}

AccessRequest* AccessPortal::requestAt(QQmlListProperty<AccessRequest>* list, qsizetype index) {
    return static_cast<AccessPortal*>(list->object)->m_requests.at(index);
}

AccessAdaptor::AccessAdaptor(AccessPortal* portal, QObject* parent) : QDBusAbstractAdaptor(parent), m_portal(portal) {}

uint AccessAdaptor::version() {
    return k_version;
}

void AccessAdaptor::AccessDialog(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
    const QString& title, const QString& subtitle, const QString& body, const QVariantMap& options,
    const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(handle, appId, title, subtitle, body, options, message);
}

} // namespace hyprstack::portals
