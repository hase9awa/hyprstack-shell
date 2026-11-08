#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qmap.h>
#include <qmetatype.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qqmlparserstatus.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

// A connection as NetworkManager passes it around: every setting by name,
// and every setting is a map of its own.
using NMConnection = QMap<QString, QVariantMap>;
Q_DECLARE_METATYPE(NMConnection)

namespace hyprstack::services {

// One secret NetworkManager is waiting on. The shell asks the user and
// answers through submit() or reject(); the request then replies to the call
// and retires itself.
class SecretRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the agent")

    // What the connection is called in NetworkManager, and what kind it is.
    Q_PROPERTY(QString connectionName READ connectionName CONSTANT)
    Q_PROPERTY(QString connectionType READ connectionType CONSTANT)
    // The setting the secret belongs to, and the key inside it.
    Q_PROPERTY(QString setting READ setting CONSTANT)
    Q_PROPERTY(QString key READ key NOTIFY keyChanged)
    Q_PROPERTY(bool hasNext READ hasNext NOTIFY keyChanged)
    Q_PROPERTY(QString message READ message CONSTANT)
    Q_PROPERTY(bool answered READ answered NOTIFY answeredChanged)

public:
    SecretRequest(QString connectionName, QString connectionType, QString setting, QString key, QString path,
        QDBusMessage call, QObject* parent = nullptr);
    SecretRequest(QString connectionName, QString connectionType, QString setting, QStringList keys, QString message,
        QString path, QDBusMessage call, QObject* parent = nullptr);

    [[nodiscard]] QString connectionName() const;
    [[nodiscard]] QString connectionType() const;
    [[nodiscard]] QString setting() const;
    [[nodiscard]] QString key() const;
    [[nodiscard]] bool hasNext() const;
    [[nodiscard]] QString message() const;
    [[nodiscard]] QString path() const;
    [[nodiscard]] bool answered() const;

    Q_INVOKABLE void submit(const QString& secret);
    Q_INVOKABLE void reject();

    // NetworkManager gave up on the question before the user answered it.
    void withdraw();

signals:
    void keyChanged();
    void answeredChanged();
    void finished();

private:
    void reply(const QDBusMessage& message);
    void finish();

    QString m_connectionName;
    QString m_connectionType;
    QString m_setting;
    QStringList m_keys;
    qsizetype m_keyIndex = 0;
    QMap<QString, QString> m_values;
    QString m_message;
    QString m_path;
    QDBusMessage m_call;
    bool m_replied = false;
    bool m_answered = false;
};

// org.freedesktop.NetworkManager.SecretAgent. A password NetworkManager does
// not have saved is asked of the registered agents, and a session without one
// simply fails to connect: nothing is asked and nothing is said. The shell
// registers one so those connections can be answered, the ones it starts
// itself with a password in hand excepted, which never reach here.
class NmSecretAgent : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)
    Q_PROPERTY(QQmlListProperty<hyprstack::services::SecretRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit NmSecretAgent(QObject* parent = nullptr);
    ~NmSecretAgent() override;
    Q_DISABLE_COPY_MOVE(NmSecretAgent)

    [[nodiscard]] bool registered() const;
    [[nodiscard]] QQmlListProperty<SecretRequest> requests();

    void classBegin() override;
    void componentComplete() override;

    void ask(const NMConnection& connection, const QString& path, const QString& setting, const QStringList& hints,
        uint flags, const QDBusMessage& call);
    void cancel(const QString& path, const QString& setting);

signals:
    void registeredChanged();
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<SecretRequest>* list);
    static SecretRequest* requestAt(QQmlListProperty<SecretRequest>* list, qsizetype index);

    void registerAgent();
    void unregisterAgent();
    void setRegistered(bool registered);

    // Carries the adaptor instead of the agent itself: the agent is a QML
    // element with properties that have no business on the bus.
    QObject m_exported;
    QList<SecretRequest*> m_requests;
    bool m_registered = false;
};

class NmSecretAgentAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.NetworkManager.SecretAgent")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.NetworkManager.SecretAgent\">\n"
        "    <method name=\"GetSecrets\">\n"
        "      <arg name=\"connection\" type=\"a{sa{sv}}\" direction=\"in\"/>\n"
        "      <arg name=\"connection_path\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"setting_name\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"hints\" type=\"as\" direction=\"in\"/>\n"
        "      <arg name=\"flags\" type=\"u\" direction=\"in\"/>\n"
        "      <arg name=\"secrets\" type=\"a{sa{sv}}\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"CancelGetSecrets\">\n"
        "      <arg name=\"connection_path\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"setting_name\" type=\"s\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"SaveSecrets\">\n"
        "      <arg name=\"connection\" type=\"a{sa{sv}}\" direction=\"in\"/>\n"
        "      <arg name=\"connection_path\" type=\"o\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"DeleteSecrets\">\n"
        "      <arg name=\"connection\" type=\"a{sa{sv}}\" direction=\"in\"/>\n"
        "      <arg name=\"connection_path\" type=\"o\" direction=\"in\"/>\n"
        "    </method>\n"
        "  </interface>\n")

public:
    explicit NmSecretAgentAdaptor(NmSecretAgent* agent, QObject* parent);

    // NOLINTBEGIN(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void GetSecrets(const NMConnection& connection, const QDBusObjectPath& path, const QString& setting,
        const QStringList& hints, uint flags, const QDBusMessage& message);
    void CancelGetSecrets(const QDBusObjectPath& path, const QString& setting);
    // The shell keeps nothing of its own: NetworkManager saves what it was
    // given, and these are here because the interface has them.
    void SaveSecrets(const NMConnection& connection, const QDBusObjectPath& path);
    void DeleteSecrets(const NMConnection& connection, const QDBusObjectPath& path);
    // NOLINTEND(readability-identifier-naming)

private:
    NmSecretAgent* m_agent;
};

} // namespace hyprstack::services
