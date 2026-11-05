#include "bluezagent.hpp"

#include <qdbusconnection.h>
#include <qdbuserror.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusservicewatcher.h>
#include <qloggingcategory.h>
#include <qvariant.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcBluez, "hyprstack.services.bluez", QtInfoMsg)

} // namespace

namespace hyprstack::services {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_service = u"org.bluez"_s;
const QString k_managerPath = u"/org/bluez"_s;
const QString k_managerIface = u"org.bluez.AgentManager1"_s;
const QString k_agentPath = u"/org/hyprstack/BluezAgent"_s;
// The shell's dialog both shows a code and takes one, which is what bluez
// calls a keyboard with a display.
const QString k_capability = u"KeyboardDisplay"_s;
const QString k_rejected = u"org.bluez.Error.Rejected"_s;
const QString k_canceled = u"org.bluez.Error.Canceled"_s;

// bluez counts a passkey as a number and shows it as six digits, zeros and
// all; the device on the other end shows the same six.
QString formatPasskey(uint passkey) {
    return QString::number(passkey).rightJustified(6, u'0');
}

} // namespace

BluezRequest::BluezRequest(
    Kind kind, QString device, QString code, QString service, QDBusMessage call, QObject* parent)
    : QObject(parent)
    , m_kind(kind)
    , m_device(std::move(device))
    , m_code(std::move(code))
    , m_service(std::move(service))
    , m_call(std::move(call)) {}

BluezRequest::Kind BluezRequest::kind() const {
    return m_kind;
}

QString BluezRequest::device() const {
    return m_device;
}

QString BluezRequest::code() const {
    return m_code;
}

QString BluezRequest::service() const {
    return m_service;
}

int BluezRequest::typed() const {
    return m_typed;
}

bool BluezRequest::answered() const {
    return m_answered;
}

void BluezRequest::accept() {
    reply(m_call.createReply());
    finish();
}

void BluezRequest::submit(const QString& code) {
    if (m_kind == AskedPasskey) {
        bool ok = false;
        const auto passkey = code.toUInt(&ok);
        if (!ok) {
            // Nothing bluez could use: refusing says so, where a zero would
            // quietly fail the pairing on the device instead.
            reject();
            return;
        }
        reply(m_call.createReply(QVariant::fromValue(passkey)));
    } else {
        reply(m_call.createReply(code));
    }

    finish();
}

void BluezRequest::reject() {
    reply(m_call.createErrorReply(k_rejected, u"The pairing was refused in the shell"_s));
    finish();
}

void BluezRequest::dismiss() {
    finish();
}

void BluezRequest::acknowledge() {
    // A shown code is answered by the method returning, so the prompt that
    // stays behind owes the call nothing.
    m_replied = true;
}

void BluezRequest::withdraw() {
    reply(m_call.createErrorReply(k_canceled, u"The pairing no longer needs an answer"_s));
    finish();
}

void BluezRequest::setTyped(int typed) {
    if (m_typed == typed)
        return;

    m_typed = typed;
    emit typedChanged();
}

void BluezRequest::reply(const QDBusMessage& message) {
    if (m_replied)
        return;

    m_replied = true;
    QDBusConnection::systemBus().send(message);
}

void BluezRequest::finish() {
    if (m_answered)
        return;

    m_answered = true;
    emit answeredChanged();

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

BluezAgent::BluezAgent(QObject* parent) : QObject(parent), m_path(k_agentPath) {}

BluezAgent::~BluezAgent() {
    unregisterAgent();
}

QString BluezAgent::path() const {
    return m_path;
}

void BluezAgent::setPath(const QString& path) {
    if (m_path == path)
        return;

    if (m_complete) {
        qCWarning(lcBluez) << "Ignoring path" << path << "set after the agent was handed to bluez";
        return;
    }

    m_path = path;
    emit pathChanged();
}

bool BluezAgent::registered() const {
    return m_registered;
}

QQmlListProperty<BluezRequest> BluezAgent::requests() {
    return { this, this, &BluezAgent::requestCount, &BluezAgent::requestAt };
}

void BluezAgent::classBegin() {}

void BluezAgent::componentComplete() {
    m_complete = true;

    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qCWarning(lcBluez) << "No system bus, pairing prompts unavailable:" << bus.lastError().message();
        return;
    }

    new BluezAgentAdaptor(this, &m_exported); // NOLINT(cppcoreguidelines-owning-memory) parented to the object
    if (!bus.registerObject(m_path, &m_exported, QDBusConnection::ExportAdaptors)) {
        qCWarning(lcBluez) << "Failed to export" << m_path << ":" << bus.lastError().message();
        return;
    }

    // bluetoothd comes and goes with the adapter, and takes every agent it
    // knew with it, so the agent is handed over again each time it returns.
    auto* watcher = new QDBusServiceWatcher(k_service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { registerAgent(); });
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        setRegistered(false);
        cancel();
    });

    registerAgent();
}

void BluezAgent::ask(BluezRequest::Kind kind, const QString& device, const QString& code, const QString& service,
    const QDBusMessage& call) {
    const auto shown = kind == BluezRequest::ShownPin || kind == BluezRequest::ShownPasskey;
    if (!shown)
        call.setDelayedReply(true);

    auto* request = new BluezRequest(kind, device, code, service, call, this);
    if (shown)
        request->acknowledge();

    add(request);
}

void BluezAgent::showPasskey(const QString& device, const QString& code, int typed, const QDBusMessage& call) {
    for (auto* request : std::as_const(m_requests)) {
        if (request->kind() != BluezRequest::ShownPasskey || request->device() != device || request->answered())
            continue;

        request->setTyped(typed);
        return;
    }

    ask(BluezRequest::ShownPasskey, device, code, {}, call);
}

void BluezAgent::cancel() {
    const auto pending = m_requests;
    for (auto* request : pending)
        request->withdraw();
}

void BluezAgent::release() {
    qCInfo(lcBluez) << "bluez took the agent back";
    setRegistered(false);
    cancel();
}

qsizetype BluezAgent::requestCount(QQmlListProperty<BluezRequest>* list) {
    return static_cast<BluezAgent*>(list->object)->m_requests.size();
}

BluezRequest* BluezAgent::requestAt(QQmlListProperty<BluezRequest>* list, qsizetype index) {
    return static_cast<BluezAgent*>(list->object)->m_requests.at(index);
}

void BluezAgent::add(BluezRequest* request) {
    connect(request, &BluezRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcBluez) << "Pairing question" << request->kind() << "for" << request->device();
}

void BluezAgent::registerAgent() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    auto msg = QDBusMessage::createMethodCall(k_service, k_managerPath, k_managerIface, u"RegisterAgent"_s);
    msg.setArguments({ QVariant::fromValue(QDBusObjectPath(m_path)), k_capability });

    const auto* watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* self) {
        const QDBusPendingReply<> reply = *self;
        self->deleteLater();

        if (reply.isError()) {
            qCWarning(lcBluez) << "bluez refused the agent:" << reply.error().message();
            return;
        }

        // Asking to be the default agent is what puts the shell in front of
        // bluetoothctl and anything else that registered one of its own.
        auto bus = QDBusConnection::systemBus();
        auto msg =
            QDBusMessage::createMethodCall(k_service, k_managerPath, k_managerIface, u"RequestDefaultAgent"_s);
        msg.setArguments({ QVariant::fromValue(QDBusObjectPath(m_path)) });
        bus.asyncCall(msg);

        setRegistered(true);
        qCInfo(lcBluez) << "Answering pairing questions as" << m_path;
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

void BluezAgent::unregisterAgent() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    if (m_registered) {
        auto msg = QDBusMessage::createMethodCall(k_service, k_managerPath, k_managerIface, u"UnregisterAgent"_s);
        msg.setArguments({ QVariant::fromValue(QDBusObjectPath(m_path)) });
        // Nothing is left to hear an answer, so the call only has to leave.
        bus.call(msg, QDBus::NoBlock);
    }

    bus.unregisterObject(m_path);
}

void BluezAgent::setRegistered(bool registered) {
    if (m_registered == registered)
        return;

    m_registered = registered;
    emit registeredChanged();
}

BluezAgentAdaptor::BluezAgentAdaptor(BluezAgent* agent, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_agent(agent) {}

void BluezAgentAdaptor::Release() {
    m_agent->release();
}

void BluezAgentAdaptor::RequestPinCode(const QDBusObjectPath& device, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::AskedPin, device.path(), {}, {}, message);
}

void BluezAgentAdaptor::DisplayPinCode(
    const QDBusObjectPath& device, const QString& pincode, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::ShownPin, device.path(), pincode, {}, message);
}

void BluezAgentAdaptor::RequestPasskey(const QDBusObjectPath& device, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::AskedPasskey, device.path(), {}, {}, message);
}

void BluezAgentAdaptor::DisplayPasskey(
    const QDBusObjectPath& device, uint passkey, ushort entered, const QDBusMessage& message) {
    m_agent->showPasskey(device.path(), formatPasskey(passkey), entered, message);
}

void BluezAgentAdaptor::RequestConfirmation(
    const QDBusObjectPath& device, uint passkey, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::Compare, device.path(), formatPasskey(passkey), {}, message);
}

void BluezAgentAdaptor::RequestAuthorization(const QDBusObjectPath& device, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::Authorize, device.path(), {}, {}, message);
}

void BluezAgentAdaptor::AuthorizeService(
    const QDBusObjectPath& device, const QString& uuid, const QDBusMessage& message) {
    m_agent->ask(BluezRequest::Service, device.path(), {}, uuid, message);
}

void BluezAgentAdaptor::Cancel() {
    m_agent->cancel();
}

} // namespace hyprstack::services
