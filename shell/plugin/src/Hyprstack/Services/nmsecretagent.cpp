#include "nmsecretagent.hpp"

#include <qdbusconnection.h>
#include <qdbuserror.h>
#include <qdbusmetatype.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusservicewatcher.h>
#include <qloggingcategory.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcSecrets, "hyprstack.services.nmsecrets", QtInfoMsg)

} // namespace

namespace hyprstack::services {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_service = u"org.freedesktop.NetworkManager"_s;
const QString k_managerPath = u"/org/freedesktop/NetworkManager/AgentManager"_s;
const QString k_managerIface = u"org.freedesktop.NetworkManager.AgentManager"_s;
const QString k_agentPath = u"/org/freedesktop/NetworkManager/SecretAgent"_s;
// NetworkManager wants agents to name themselves the way a bus name is named.
const QString k_identifier = u"org.hyprstack.shell"_s;
const QString k_canceled = u"org.freedesktop.NetworkManager.SecretAgent.UserCanceled"_s;
const QString k_noSecrets = u"org.freedesktop.NetworkManager.SecretAgent.NoSecrets"_s;

// Without this flag the question is not meant for the user at all: it is
// NetworkManager looking through what the agents have saved, and the shell
// saves nothing.
constexpr uint k_allowInteraction = 0x1;

// What the connection calls itself, for the prompt to name it by.
QString nameOf(const NMConnection& connection) {
    return connection.value(u"connection"_s).value(u"id"_s).toString();
}

QString typeOf(const NMConnection& connection) {
    return connection.value(u"connection"_s).value(u"type"_s).toString();
}

// Which key inside the setting is wanted. NetworkManager names it in the
// hints whenever it knows, and the rest is what each setting keeps its
// password under.
QString defaultKey(const NMConnection& connection, const QString& setting) {
    if (setting == u"802-11-wireless-security"_s) {
        const auto keyMgmt = connection.value(setting).value(u"key-mgmt"_s).toString();
        if (keyMgmt == u"none"_s)
            return u"wep-key%1"_s.arg(qBound(0, connection.value(setting).value(u"wep-tx-keyidx"_s).toInt(), 3));
        if (keyMgmt == u"ieee8021x"_s)
            return u"leap-password"_s;
        return u"psk"_s;
    }

    if (setting == u"wireguard"_s)
        return u"private-key"_s;

    return u"password"_s;
}

} // namespace

SecretRequest::SecretRequest(QString connectionName, QString connectionType, QString setting, QString key,
    QString path, QDBusMessage call, QObject* parent)
    : SecretRequest(std::move(connectionName), std::move(connectionType), std::move(setting),
        QStringList{std::move(key)}, {}, std::move(path), std::move(call), parent) {}

SecretRequest::SecretRequest(QString connectionName, QString connectionType, QString setting, QStringList keys,
    QString message, QString path, QDBusMessage call, QObject* parent)
    : QObject(parent)
    , m_connectionName(std::move(connectionName))
    , m_connectionType(std::move(connectionType))
    , m_setting(std::move(setting))
    , m_keys(std::move(keys))
    , m_message(std::move(message))
    , m_path(std::move(path))
    , m_call(std::move(call)) {}

QString SecretRequest::connectionName() const {
    return m_connectionName;
}

QString SecretRequest::connectionType() const {
    return m_connectionType;
}

QString SecretRequest::setting() const {
    return m_setting;
}

QString SecretRequest::key() const {
    return m_keys.value(m_keyIndex);
}

bool SecretRequest::hasNext() const { return m_keyIndex + 1 < m_keys.size(); }
QString SecretRequest::message() const { return m_message; }

QString SecretRequest::path() const {
    return m_path;
}

bool SecretRequest::answered() const {
    return m_answered;
}

void SecretRequest::submit(const QString& secret) {
    if (m_answered || key().isEmpty())
        return;
    m_values.insert(key(), secret);
    if (hasNext()) {
        ++m_keyIndex;
        emit keyChanged();
        return;
    }
    NMConnection answer;
    if (m_setting == u"vpn"_s) {
        // A VPN keeps its secrets one map deeper, under the plugin's own
        // names, and all of them are plain strings.
        answer.insert(m_setting, QVariantMap { { u"secrets"_s, QVariant::fromValue(m_values) } });
    } else {
        QVariantMap values;
        for (auto it = m_values.cbegin(); it != m_values.cend(); ++it)
            values.insert(it.key(), it.value());
        answer.insert(m_setting, values);
    }

    reply(m_call.createReply(QVariant::fromValue(answer)));
    finish();
}

void SecretRequest::reject() {
    reply(m_call.createErrorReply(k_canceled, u"The password was not given in the shell"_s));
    finish();
}

void SecretRequest::withdraw() {
    reply(m_call.createErrorReply(k_canceled, u"NetworkManager withdrew the request"_s));
    finish();
}

void SecretRequest::reply(const QDBusMessage& message) {
    if (m_replied)
        return;

    m_replied = true;
    QDBusConnection::systemBus().send(message);
}

void SecretRequest::finish() {
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

NmSecretAgent::NmSecretAgent(QObject* parent) : QObject(parent) {
    qDBusRegisterMetaType<NMConnection>();
    qDBusRegisterMetaType<QMap<QString, QString>>();
}

NmSecretAgent::~NmSecretAgent() {
    unregisterAgent();
}

bool NmSecretAgent::registered() const {
    return m_registered;
}

QQmlListProperty<SecretRequest> NmSecretAgent::requests() {
    return { this, this, &NmSecretAgent::requestCount, &NmSecretAgent::requestAt };
}

void NmSecretAgent::classBegin() {}

void NmSecretAgent::componentComplete() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qCWarning(lcSecrets) << "No system bus, password prompts unavailable:" << bus.lastError().message();
        return;
    }

    new NmSecretAgentAdaptor(this, &m_exported); // NOLINT(cppcoreguidelines-owning-memory) parented to the object
    if (!bus.registerObject(k_agentPath, &m_exported, QDBusConnection::ExportAdaptors)) {
        qCWarning(lcSecrets) << "Failed to export" << k_agentPath << ":" << bus.lastError().message();
        return;
    }

    // NetworkManager forgets its agents when it restarts, so the shell hands
    // itself over again each time it comes back.
    auto* watcher = new QDBusServiceWatcher(k_service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { registerAgent(); });
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        setRegistered(false);
        const auto pending = m_requests;
        for (auto* request : pending)
            request->withdraw();
    });

    registerAgent();
}

void NmSecretAgent::ask(const NMConnection& connection, const QString& path, const QString& setting,
    const QStringList& hints, uint flags, const QDBusMessage& call) {
    if ((flags & k_allowInteraction) == 0) {
        QDBusConnection::systemBus().send(
            call.createErrorReply(k_noSecrets, u"The shell keeps no secrets of its own"_s));
        return;
    }

    call.setDelayedReply(true);

    QStringList keys;
    QString message;
    for (const auto& hint : hints) {
        if (hint.startsWith(u"x-vpn-message:")) {
            message = hint.mid(14);
        } else if (!hint.isEmpty() && !hint.startsWith(u"x-vpn-") && !keys.contains(hint)) {
            keys.append(hint);
        }
    }
    if (keys.isEmpty()) keys.append(defaultKey(connection, setting));
    auto* request = new SecretRequest(nameOf(connection), typeOf(connection), setting,
        keys, message, path, call, this);

    connect(request, &SecretRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcSecrets) << "Password wanted for" << request->connectionName() << "-" << setting << request->key();
}

void NmSecretAgent::cancel(const QString& path, const QString& setting) {
    const auto pending = m_requests;
    for (auto* request : pending)
        if (request->path() == path && request->setting() == setting)
            request->withdraw();
}

qsizetype NmSecretAgent::requestCount(QQmlListProperty<SecretRequest>* list) {
    return static_cast<NmSecretAgent*>(list->object)->m_requests.size();
}

SecretRequest* NmSecretAgent::requestAt(QQmlListProperty<SecretRequest>* list, qsizetype index) {
    return static_cast<NmSecretAgent*>(list->object)->m_requests.at(index);
}

void NmSecretAgent::registerAgent() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    auto msg = QDBusMessage::createMethodCall(k_service, k_managerPath, k_managerIface, u"Register"_s);
    msg.setArguments({ k_identifier });

    const auto* watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* self) {
        const QDBusPendingReply<> reply = *self;
        self->deleteLater();

        if (reply.isError()) {
            qCWarning(lcSecrets) << "NetworkManager refused the agent:" << reply.error().message();
            return;
        }

        setRegistered(true);
        qCInfo(lcSecrets) << "Answering password requests as" << k_identifier;
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

void NmSecretAgent::unregisterAgent() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    if (m_registered) {
        auto msg = QDBusMessage::createMethodCall(k_service, k_managerPath, k_managerIface, u"Unregister"_s);
        // Nothing is left to hear an answer, so the call only has to leave.
        bus.call(msg, QDBus::NoBlock);
    }

    bus.unregisterObject(k_agentPath);
}

void NmSecretAgent::setRegistered(bool registered) {
    if (m_registered == registered)
        return;

    m_registered = registered;
    emit registeredChanged();
}

NmSecretAgentAdaptor::NmSecretAgentAdaptor(NmSecretAgent* agent, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_agent(agent) {}

void NmSecretAgentAdaptor::GetSecrets(const NMConnection& connection, const QDBusObjectPath& path,
    const QString& setting, const QStringList& hints, uint flags, const QDBusMessage& message) {
    m_agent->ask(connection, path.path(), setting, hints, flags, message);
}

void NmSecretAgentAdaptor::CancelGetSecrets(const QDBusObjectPath& path, const QString& setting) {
    m_agent->cancel(path.path(), setting);
}

void NmSecretAgentAdaptor::SaveSecrets(const NMConnection& connection, const QDBusObjectPath& path) {
    Q_UNUSED(connection)
    Q_UNUSED(path)
}

void NmSecretAgentAdaptor::DeleteSecrets(const NMConnection& connection, const QDBusObjectPath& path) {
    Q_UNUSED(connection)
    Q_UNUSED(path)
}

} // namespace hyprstack::services
