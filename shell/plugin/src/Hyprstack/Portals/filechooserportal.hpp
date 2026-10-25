#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusargument.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qlist.h>
#include <qmetatype.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include "portal.hpp"

namespace hyprstack::portals {

// One line of a file filter as it travels on the bus: a glob pattern or a
// MIME type, tagged by kind.
struct FileFilterRule {
    uint kind = 0;
    QString value;
};

// A named filter the chooser offers, such as "Images" with its patterns.
struct FileFilter {
    QString label;
    QList<FileFilterRule> rules;
};

QDBusArgument& operator<<(QDBusArgument& argument, const FileFilterRule& rule);
const QDBusArgument& operator>>(const QDBusArgument& argument, FileFilterRule& rule);
QDBusArgument& operator<<(QDBusArgument& argument, const FileFilter& filter);
const QDBusArgument& operator>>(const QDBusArgument& argument, FileFilter& filter);

// One chooser an application is waiting on. The shell shows a dialog for it
// and answers through accept() or reject(); the request then replies to the
// pending call and retires itself.
class FileChooserRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Requests are created by the file chooser portal")

    Q_PROPERTY(Action action READ action CONSTANT)
    Q_PROPERTY(QString appId READ appId CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString acceptLabel READ acceptLabel CONSTANT)
    Q_PROPERTY(bool multiple READ multiple CONSTANT)
    Q_PROPERTY(bool directory READ directory CONSTANT)
    Q_PROPERTY(QString currentFolder READ currentFolder CONSTANT)
    Q_PROPERTY(QString currentName READ currentName CONSTANT)
    // SaveFiles names the files up front and asks only for their folder.
    Q_PROPERTY(QStringList fileNames READ fileNames CONSTANT)
    // Each entry is {label, patterns, mimeTypes}; -1 selects no filter.
    Q_PROPERTY(QVariantList filters READ filters CONSTANT)
    Q_PROPERTY(int currentFilter READ currentFilter CONSTANT)
    Q_PROPERTY(bool answered READ answered NOTIFY answeredChanged)

public:
    enum class Action : quint8 {
        Open,
        Save,
        SaveMultiple,
    };
    Q_ENUM(Action)

    FileChooserRequest(Action action, QString appId, QString title, QVariantMap options, QDBusMessage call,
        QDBusObjectPath handle, QObject* parent = nullptr);

    [[nodiscard]] Action action() const;
    [[nodiscard]] QString appId() const;
    [[nodiscard]] QString title() const;
    [[nodiscard]] QString acceptLabel() const;
    [[nodiscard]] bool multiple() const;
    [[nodiscard]] bool directory() const;
    [[nodiscard]] QString currentFolder() const;
    [[nodiscard]] QString currentName() const;
    [[nodiscard]] QStringList fileNames() const;
    [[nodiscard]] QVariantList filters() const;
    [[nodiscard]] int currentFilter() const;
    [[nodiscard]] bool answered() const;
    [[nodiscard]] QDBusObjectPath handle() const;

    // Paths are local file names; the portal turns them into file:// URIs.
    Q_INVOKABLE void accept(const QStringList& paths, int filter = -1);
    Q_INVOKABLE void reject();

    // The application withdrew the request before the user answered.
    void close();

signals:
    void answeredChanged();
    void finished();

private:
    void respond(uint response, const QVariantMap& results);

    Action m_action;
    QString m_appId;
    QString m_title;
    QVariantMap m_options;
    QDBusMessage m_call;
    QDBusObjectPath m_handle;
    QList<FileFilter> m_filters;
    bool m_answered = false;
};

// org.freedesktop.impl.portal.FileChooser. The shell answers file dialogs for
// applications that cannot draw one themselves, sandboxed ones in particular.
class FileChooserPortal : public Portal {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQmlListProperty<hyprstack::portals::FileChooserRequest> requests READ requests NOTIFY requestsChanged)

public:
    explicit FileChooserPortal(QObject* parent = nullptr);

    void exportOn(QObject* target) override;
    [[nodiscard]] QString interfaceName() const override;

    [[nodiscard]] QQmlListProperty<FileChooserRequest> requests();

    void add(FileChooserRequest::Action action, const QDBusObjectPath& handle, const QString& appId,
        const QString& title, const QVariantMap& options, const QDBusMessage& call);

signals:
    void requestsChanged();

private:
    static qsizetype requestCount(QQmlListProperty<FileChooserRequest>* list);
    static FileChooserRequest* requestAt(QQmlListProperty<FileChooserRequest>* list, qsizetype index);

    QList<FileChooserRequest*> m_requests;
};

// org.freedesktop.impl.portal.Request, exported on the handle the caller
// chose so it can withdraw a dialog it no longer needs.
class RequestAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.Request\">\n"
        "    <method name=\"Close\"/>\n"
        "  </interface>\n")

public:
    explicit RequestAdaptor(FileChooserRequest* request);

    // NOLINTNEXTLINE(readability-identifier-naming) D-Bus spells it this way
public slots:
    void Close();

private:
    FileChooserRequest* m_request;
};

class FileChooserAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.FileChooser\">\n"
        "    <property name=\"version\" type=\"u\" access=\"read\"/>\n"
        "    <method name=\"OpenFile\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "      <arg name=\"results\" type=\"a{sv}\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"SaveFile\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "      <arg name=\"results\" type=\"a{sv}\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"SaveFiles\">\n"
        "      <arg name=\"handle\" type=\"o\" direction=\"in\"/>\n"
        "      <arg name=\"app_id\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
        "      <arg name=\"response\" type=\"u\" direction=\"out\"/>\n"
        "      <arg name=\"results\" type=\"a{sv}\" direction=\"out\"/>\n"
        "    </method>\n"
        "  </interface>\n")

    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit FileChooserAdaptor(FileChooserPortal* portal, QObject* parent);

    [[nodiscard]] static uint version();

    // NOLINTBEGIN(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    void OpenFile(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QString& title, const QVariantMap& options, const QDBusMessage& message);
    void SaveFile(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QString& title, const QVariantMap& options, const QDBusMessage& message);
    void SaveFiles(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
        const QString& title, const QVariantMap& options, const QDBusMessage& message);
    // NOLINTEND(readability-identifier-naming)

private:
    FileChooserPortal* m_portal;
};

} // namespace hyprstack::portals

Q_DECLARE_METATYPE(hyprstack::portals::FileFilterRule)
Q_DECLARE_METATYPE(hyprstack::portals::FileFilter)
