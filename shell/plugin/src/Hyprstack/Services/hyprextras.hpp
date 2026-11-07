#pragma once

#include <qlocalsocket.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qpointer.h>
#include <qvariant.h>

namespace hyprstack::services::hypr {

class HyprDevices;

class HyprExtras : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_MOC_INCLUDE("hyprdevices.hpp")

    Q_PROPERTY(QVariantHash options READ options NOTIFY optionsChanged)
    Q_PROPERTY(hyprstack::services::hypr::HyprDevices* devices READ devices CONSTANT)
    Q_PROPERTY(bool usingLua MEMBER m_usingLua NOTIFY usingLuaChanged)
    Q_PROPERTY(QVariantHash clients READ clients NOTIFY clientsChanged)
    Q_PROPERTY(bool clientsReady READ clientsReady NOTIFY clientsChanged)

public:
    explicit HyprExtras(QObject* parent = nullptr);

    [[nodiscard]] QVariantHash options() const;
    [[nodiscard]] HyprDevices* devices() const;
    [[nodiscard]] QVariantHash clients() const;
    [[nodiscard]] bool clientsReady() const;

    Q_INVOKABLE void message(const QString& message);
    Q_INVOKABLE void batchMessage(const QStringList& messages);
    Q_INVOKABLE void applyOptions(const QVariantHash& options);

    Q_INVOKABLE void refreshOptions();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void refreshClients();

signals:
    void optionsChanged();
    void usingLuaChanged();
    void clientsChanged();

private:
    using SocketPtr = QPointer<QLocalSocket>;

    QString m_requestSocket;
    QString m_eventSocket;
    QLocalSocket* m_socket;
    bool m_socketValid;
    bool m_usingLua = false;

    QVariantHash m_options;
    HyprDevices* const m_devices;

    SocketPtr m_optionsRefresh;
    SocketPtr m_devicesRefresh;
    SocketPtr m_clientsRefresh;
    QVariantHash m_clients;
    bool m_clientsReady = false;
    bool m_clientsPending = false;

    void socketError(QLocalSocket::LocalSocketError error) const;
    void socketStateChanged(QLocalSocket::LocalSocketState state);
    void readEvent();
    void handleEvent(const QString& event);

    SocketPtr makeRequestJson(const QString& request, const std::function<void(bool, QJsonDocument)>& callback);
    SocketPtr makeRequest(const QString& request, const std::function<void(bool, QByteArray)>& callback);
};

} // namespace hyprstack::services::hypr
