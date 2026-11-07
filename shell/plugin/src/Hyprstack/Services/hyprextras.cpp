#include "hyprextras.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qjsonobject.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qvariant.h>
#include <qtimer.h>

#include <memory>

#include "hyprdevices.hpp"

namespace {

Q_LOGGING_CATEGORY(lcHypr, "hyprstack.services.hypr", QtInfoMsg)

} // namespace

namespace hyprstack::services::hypr {

using Qt::StringLiterals::operator""_s;

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qCWarning(lcHypr) << "$HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = u"%1/hypr/%2"_s.arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = u"/tmp/hypr/"_s + his;

        if (!QDir(hyprDir).exists()) {
            qCWarning(lcHypr) << "Hyprland socket directory does not exist. Unable to connect to Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + u"/.socket.sock"_s;
    m_eventSocket = hyprDir + u"/.socket2.sock"_s;

    refreshOptions();
    refreshDevices();
    refreshClients();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

HyprDevices* HyprExtras::devices() const {
    return m_devices;
}

QVariantHash HyprExtras::clients() const {
    return m_clients;
}

bool HyprExtras::clientsReady() const {
    return m_clientsReady;
}

void HyprExtras::refreshClients() {
    if (m_clientsRefresh) {
        m_clientsPending = true;
        return;
    }
    m_clientsPending = false;
    m_clientsRefresh = makeRequestJson(u"clients"_s, [this](bool success, const QJsonDocument& response) {
        m_clientsRefresh = nullptr;
        if (success && response.isArray()) {
            QVariantHash clients;
            for (const auto& value : response.array()) {
                const auto client = value.toObject().toVariantMap();
                const auto address = client.value(u"address"_s).toString();
                if (!address.isEmpty()) {
                    clients.insert(address, client);
                }
            }
            // Replace the entire snapshot: disappeared windows must be removed,
            // even if an older Quickshell reply recreated their model objects.
            if (!m_clientsReady || clients != m_clients) {
                m_clients = std::move(clients);
                m_clientsReady = true;
                emit clientsChanged();
            }
        }
        // An event received during the query needs a fresh request, rather than
        // another fixed-delay request that can also be dropped while busy.
        if (m_clientsPending) {
            refreshClients();
        }
    });
}

void HyprExtras::message(const QString& message) {
    if (message.isEmpty()) {
        return;
    }

    makeRequest(message, [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "message: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::batchMessage(const QStringList& messages) {
    if (messages.isEmpty()) {
        return;
    }

    makeRequest(u"[[BATCH]]"_s + messages.join(u";"_s), [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "batchMessage: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    QString request;
    request.reserve(12 + options.size() * 40);
    request += u"[[BATCH]]"_s;
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        if (!m_usingLua) {
            request += u"keyword "_s + it.key() + u' ' + it.value().toString() + u';';
        } else {
            const auto parts = it.key().split(u':');
            request += u"eval hl.config({ "_s + parts.join(u" = { "_s) + u" = "_s + it.value().toString() +
                       u" }"_s.repeated(parts.size() - 1) + u" });"_s;
        }
    }

    makeRequest(request, [this](bool success, const QByteArray& res) {
        if (success) {
            refreshOptions();
        } else {
            qCWarning(lcHypr) << "applyOptions: request error" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::refreshOptions() {
    if (!m_optionsRefresh.isNull()) {
        m_optionsRefresh->disconnect(this);
        m_optionsRefresh->abort();
        m_optionsRefresh->deleteLater();
    }

    m_optionsRefresh = makeRequestJson(u"descriptions"_s, [this](bool success, const QJsonDocument& response) {
        m_optionsRefresh.clear();
        if (!success) {
            return;
        }

        const auto options = response.array();
        bool dirty = false;

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();
            const auto key = obj.value(u"value"_s).toString();
            const auto value = obj.value(u"data"_s).toObject().value(u"current"_s).toVariant();
            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }
    });
}

void HyprExtras::refreshDevices() {
    if (!m_devicesRefresh.isNull()) {
        m_devicesRefresh->disconnect(this);
        m_devicesRefresh->abort();
        m_devicesRefresh->deleteLater();
    }

    m_devicesRefresh = makeRequestJson(u"devices"_s, [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.clear();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }
    });
}

void HyprExtras::socketError(QLocalSocket::LocalSocketError error) const {
    if (!m_socketValid) {
        qCWarning(lcHypr) << "socketError: unable to connect to Hyprland event socket:" << error;
    } else {
        qCWarning(lcHypr) << "socketError: Hyprland event socket error:" << error;
    }
}

void HyprExtras::socketStateChanged(QLocalSocket::LocalSocketState state) {
    if (state == QLocalSocket::UnconnectedState && m_socketValid) {
        qCWarning(lcHypr) << "socketStateChanged: Hyprland event socket disconnected.";
    }

    m_socketValid = state == QLocalSocket::ConnectedState;
}

void HyprExtras::readEvent() {
    while (m_socket->canReadLine()) {
        auto rawEvent = m_socket->readLine();
        if (rawEvent.isEmpty()) {
            break;
        }
        rawEvent.truncate(rawEvent.length() - 1); // Remove trailing \n
        const auto sep = rawEvent.indexOf(">>");
        if (sep < 0) {
            qCWarning(lcHypr) << "readEvent: malformed event (no >> separator):" << rawEvent;
            continue;
        }
        handleEvent(QString::fromUtf8(QByteArrayView(rawEvent.data(), sep)));
    }
}

void HyprExtras::handleEvent(const QString& event) {
    if (event == u"configreloaded"_s) {
        refreshOptions();
    } else if (event == u"activelayout"_s) {
        refreshDevices();
    }
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest(u"j/"_s + request, [callback](bool success, const QByteArray& response) {
        QJsonParseError error;
        auto document = QJsonDocument::fromJson(response, &error);
        callback(success && error.error == QJsonParseError::NoError, document);
    });
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return {};
    }

    auto* const socket = new QLocalSocket(this);
    auto* const timer = new QTimer(socket);
    timer->setSingleShot(true);
    struct Response {
        QByteArray bytes;
        bool finished = false;
    };
    const auto response = std::make_shared<Response>();
    const auto finish = [socket, timer, response, callback](bool success) {
        if (response->finished)
            return;
        response->finished = true;
        timer->stop();
        response->bytes += socket->readAll();
        socket->deleteLater();
        callback(success, std::move(response->bytes));
    };
    QObject::connect(socket, &QLocalSocket::connected, this, [socket, request] {
        socket->write(request.toUtf8());
        socket->flush();
    });
    QObject::connect(socket, &QLocalSocket::readyRead, this, [socket, response, finish] {
        response->bytes += socket->readAll();
        if (response->bytes.size() > 16 * 1024 * 1024)
            finish(false);
    });
    QObject::connect(socket, &QLocalSocket::disconnected, this, [finish] { finish(true); });
    QObject::connect(socket, &QLocalSocket::errorOccurred, this, [finish](QLocalSocket::LocalSocketError error) {
        // EOF is delivered as PeerClosedError followed by disconnected.
        if (error != QLocalSocket::PeerClosedError)
            finish(false);
    });
    QObject::connect(timer, &QTimer::timeout, this, [finish] { finish(false); });
    timer->start(5000);
    socket->connectToServer(m_requestSocket);
    return SocketPtr(socket);
}

} // namespace hyprstack::services::hypr
