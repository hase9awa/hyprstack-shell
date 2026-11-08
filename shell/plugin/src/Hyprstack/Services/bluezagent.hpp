#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qqmlparserstatus.h>
#include <qstring.h>

namespace hyprstack::services {

// One question bluez asks while a device pairs. The shell puts it to the user
// and answers through accept(), submit() or reject(); the request then replies
// to the call bluez is waiting on and retires itself.
class BluezRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the agent")

    Q_PROPERTY(Kind kind READ kind CONSTANT)
    // The device's own object path, which is how the shell tells its devices
    // apart; bluez names nothing else in the question.
    Q_PROPERTY(QString device READ device CONSTANT)
    Q_PROPERTY(QString code READ code CONSTANT)
    Q_PROPERTY(QString service READ service CONSTANT)
    Q_PROPERTY(int typed READ typed NOTIFY typedChanged)
    Q_PROPERTY(bool answered READ answered NOTIFY answeredChanged)

public:
    // What is being asked. The two shown kinds only tell the user something,
    // and are already answered by the time the prompt is up.
    enum Kind : quint8 {
        Compare,     // the same code is on both ends: do they match?
        Authorize,   // a device asks to pair, with no code to compare
        Service,     // a paired device asks for one of its services
        ShownPin,    // this pin is to be typed on the device
        ShownPasskey, // this code is to be typed on the device
        AskedPin,    // the device shows a pin, which the user types here
        AskedPasskey, // the device shows a code, which the user types here
    };
    Q_ENUM(Kind)

    BluezRequest(Kind kind, QString device, QString code, QString service, QDBusMessage call,
        QObject* parent = nullptr);

    [[nodiscard]] Kind kind() const;
    [[nodiscard]] QString device() const;
    [[nodiscard]] QString code() const;
    [[nodiscard]] QString service() const;
    [[nodiscard]] int typed() const;
    [[nodiscard]] bool answered() const;

    // Agrees to a question that has nothing to type into it.
    Q_INVOKABLE void accept();
    // Answers one that has: a pin as it was typed, a passkey as a number.
    Q_INVOKABLE void submit(const QString& code);
    // Refuses the pairing.
    Q_INVOKABLE void reject();
    // Takes a prompt off the screen without answering, which is all that is
    // left to do with one that was only showing a code.
    Q_INVOKABLE void dismiss();

    // Replies the moment the prompt goes up, for the kinds bluez expects an
    // answer to straight away and withdraws itself.
    void acknowledge();
    // bluez no longer needs this one: the pairing moved on without it.
    void withdraw();
    // How much of a shown code the device has taken so far.
    void setTyped(int typed);

signals:
    void typedChanged();
    void answeredChanged();
    void finished();

private:
    void reply(const QDBusMessage& message);
    void finish();

    Kind m_kind;
    QString m_device;
    QString m_code;
    QString m_service;
    QDBusMessage m_call;
    int m_typed = 0;
    bool m_replied = false;
    bool m_answered = false;
};

// org.bluez.Agent1. Pairing anything that has a code to compare or to type
// needs an agent registered on the system bus: bluez refuses the pairing
// outright when nobody is there to ask, so the shell registers one and shows
// what it asks. The agent says it can both display a code and take one, which
// is what the shell's own dialog does.
class BluezAgent : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)
    Q_PROPERTY(QQmlListProperty<hyprstack::services::BluezRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit BluezAgent(QObject* parent = nullptr);
    ~BluezAgent() override;
    Q_DISABLE_COPY_MOVE(BluezAgent)

    [[nodiscard]] QString path() const;
    void setPath(const QString& path);
    [[nodiscard]] bool registered() const;
    [[nodiscard]] QQmlListProperty<BluezRequest> requests();

    void classBegin() override;
    void componentComplete() override;

    // Puts a question on the list the dialogs follow.
    void ask(BluezRequest::Kind kind, const QString& device, const QString& code, const QString& service,
        const QDBusMessage& call);
    // A code the device takes a digit at a time is asked again for every
    // digit: the same prompt, counted on rather than a second one.
    void showPasskey(const QString& device, const QString& code, int typed, const QDBusMessage& call);
    // bluez withdrew whatever it was asking.
    void cancel();
    // bluez took the agent away; it has to be handed back before it is used.
    void release();

signals:
    void pathChanged();
    void registeredChanged();
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<BluezRequest>* list);
    static BluezRequest* requestAt(QQmlListProperty<BluezRequest>* list, qsizetype index);

    void add(BluezRequest* request);
    void registerAgent();
    void unregisterAgent();
    void setRegistered(bool registered);

    // Carries the adaptor instead of the agent itself: the agent is a QML
    // element with properties that have no business on the bus.
    QObject m_exported;
    QList<BluezRequest*> m_requests;
    QString m_path;
    bool m_complete = false;
    bool m_registered = false;
};

class BluezAgentAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.bluez.Agent1\">\n"
        "    <method name=\"Release\"/>\n"
        "    <method name=\"RequestPinCode\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"pincode\" type=\"s\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"DisplayPinCode\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"pincode\" type=\"s\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"RequestPasskey\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"passkey\" type=\"u\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"DisplayPasskey\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"passkey\" type=\"u\" direction=\"in\"/>\n"
        "      <arg name=\"entered\" type=\"q\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"RequestConfirmation\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"passkey\" type=\"u\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"RequestAuthorization\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"AuthorizeService\">\n"
        "      <arg name=\"device\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"uuid\" type=\"s\" direction=\"in\"/>\n"
        "    </method>\n"
        "    <method name=\"Cancel\"/>\n"
        "  </interface>\n")

public:
    explicit BluezAgentAdaptor(BluezAgent* agent, QObject* parent);

    // NOLINTBEGIN(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void Release();
    void RequestPinCode(const QDBusObjectPath& device, const QDBusMessage& message);
    void DisplayPinCode(const QDBusObjectPath& device, const QString& pincode, const QDBusMessage& message);
    void RequestPasskey(const QDBusObjectPath& device, const QDBusMessage& message);
    void DisplayPasskey(
        const QDBusObjectPath& device, uint passkey, ushort entered, const QDBusMessage& message);
    void RequestConfirmation(const QDBusObjectPath& device, uint passkey, const QDBusMessage& message);
    void RequestAuthorization(const QDBusObjectPath& device, const QDBusMessage& message);
    void AuthorizeService(const QDBusObjectPath& device, const QString& uuid, const QDBusMessage& message);
    void Cancel();
    // NOLINTEND(readability-identifier-naming)

private:
    BluezAgent* m_agent;
};

} // namespace hyprstack::services
