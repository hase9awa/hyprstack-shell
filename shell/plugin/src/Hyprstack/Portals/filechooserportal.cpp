#include "filechooserportal.hpp"

#include <qdbusconnection.h>
#include <qdbusmetatype.h>
#include <qfileinfo.h>
#include <qloggingcategory.h>
#include <qurl.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcFileChooser, "hyprstack.portals.filechooser", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_interface = u"org.freedesktop.impl.portal.FileChooser"_s;

constexpr uint k_version = 3;
constexpr uint k_responseSuccess = 0;
constexpr uint k_responseCancelled = 1;
constexpr uint k_responseOther = 2;

constexpr uint k_ruleGlob = 0;
constexpr uint k_ruleMimeType = 1;

// The portal passes paths as NUL terminated byte arrays.
QString pathFromOption(const QVariant& value) {
    const auto bytes = value.toByteArray();
    const auto end = bytes.indexOf('\0');
    return QFile::decodeName(end < 0 ? bytes : bytes.left(end));
}

template<typename T>
T demarshal(const QVariant& value) {
    T result;
    if (value.canConvert<QDBusArgument>())
        value.value<QDBusArgument>() >> result;
    return result;
}

} // namespace

QDBusArgument& operator<<(QDBusArgument& argument, const FileFilterRule& rule) {
    argument.beginStructure();
    argument << rule.kind << rule.value;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, FileFilterRule& rule) {
    argument.beginStructure();
    argument >> rule.kind >> rule.value;
    argument.endStructure();
    return argument;
}

QDBusArgument& operator<<(QDBusArgument& argument, const FileFilter& filter) {
    argument.beginStructure();
    argument << filter.label << filter.rules;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, FileFilter& filter) {
    argument.beginStructure();
    argument >> filter.label >> filter.rules;
    argument.endStructure();
    return argument;
}

FileChooserRequest::FileChooserRequest(Action action, QString appId, QString title, QVariantMap options,
    QDBusMessage call, QDBusObjectPath handle, QObject* parent)
    : QObject(parent)
    , m_action(action)
    , m_appId(std::move(appId))
    , m_title(std::move(title))
    , m_options(std::move(options))
    , m_call(std::move(call))
    , m_handle(std::move(handle))
    , m_filters(demarshal<QList<FileFilter>>(m_options.value(u"filters"_s))) {}

FileChooserRequest::Action FileChooserRequest::action() const {
    return m_action;
}

QString FileChooserRequest::appId() const {
    return m_appId;
}

QString FileChooserRequest::title() const {
    return m_title;
}

QString FileChooserRequest::acceptLabel() const {
    // Toolkits mark the accelerator with an underscore the shell does not use.
    return m_options.value(u"accept_label"_s).toString().remove(u'_');
}

bool FileChooserRequest::multiple() const {
    return m_options.value(u"multiple"_s).toBool();
}

bool FileChooserRequest::directory() const {
    return m_options.value(u"directory"_s).toBool();
}

QString FileChooserRequest::currentFolder() const {
    return pathFromOption(m_options.value(u"current_folder"_s));
}

QString FileChooserRequest::currentName() const {
    return m_options.value(u"current_name"_s).toString();
}

QStringList FileChooserRequest::fileNames() const {
    QStringList names;
    for (const auto& name : demarshal<QList<QByteArray>>(m_options.value(u"files"_s)))
        names.append(pathFromOption(QVariant::fromValue(name)));
    return names;
}

QVariantList FileChooserRequest::filters() const {
    QVariantList result;
    result.reserve(m_filters.size());

    for (const auto& filter : m_filters) {
        QStringList patterns;
        QStringList mimeTypes;
        for (const auto& rule : filter.rules) {
            if (rule.kind == k_ruleGlob)
                patterns.append(rule.value);
            else if (rule.kind == k_ruleMimeType)
                mimeTypes.append(rule.value);
        }
        result.append(QVariantMap {
            { u"label"_s, filter.label },
            { u"patterns"_s, patterns },
            { u"mimeTypes"_s, mimeTypes },
        });
    }

    return result;
}

int FileChooserRequest::currentFilter() const {
    const auto selected = demarshal<FileFilter>(m_options.value(u"current_filter"_s));
    if (selected.label.isEmpty())
        return -1;

    for (qsizetype i = 0; i < m_filters.size(); ++i) {
        if (m_filters.at(i).label == selected.label)
            return static_cast<int>(i);
    }

    return -1;
}

bool FileChooserRequest::answered() const {
    return m_answered;
}

QDBusObjectPath FileChooserRequest::handle() const {
    return m_handle;
}

void FileChooserRequest::accept(const QStringList& paths, int filter) {
    if (paths.isEmpty()) {
        reject();
        return;
    }

    QStringList uris;
    uris.reserve(paths.size());
    for (const auto& path : paths)
        uris.append(QUrl::fromLocalFile(QFileInfo(path).absoluteFilePath()).toString());

    QVariantMap results { { u"uris"_s, uris }, { u"writable"_s, m_action != Action::Open } };
    if (filter >= 0 && filter < m_filters.size())
        results.insert(u"current_filter"_s, QVariant::fromValue(m_filters.at(filter)));

    respond(k_responseSuccess, results);
}

void FileChooserRequest::reject() {
    respond(k_responseCancelled, {});
}

void FileChooserRequest::close() {
    qCDebug(lcFileChooser) << "Request withdrawn by" << m_appId;
    respond(k_responseOther, {});
}

void FileChooserRequest::respond(uint response, const QVariantMap& results) {
    if (m_answered)
        return;

    m_answered = true;
    emit answeredChanged();

    auto bus = QDBusConnection::sessionBus();
    bus.send(m_call.createReply({ QVariant::fromValue(response), QVariant::fromValue(results) }));
    bus.unregisterObject(m_handle.path());

    emit finished();
    deleteLater();
}

FileChooserPortal::FileChooserPortal(QObject* parent) : Portal(parent) {
    qDBusRegisterMetaType<FileFilterRule>();
    qDBusRegisterMetaType<QList<FileFilterRule>>();
    qDBusRegisterMetaType<FileFilter>();
    qDBusRegisterMetaType<QList<FileFilter>>();
}

void FileChooserPortal::exportOn(QObject* target) {
    new FileChooserAdaptor(this, target); // NOLINT(cppcoreguidelines-owning-memory) parented to target
}

QString FileChooserPortal::interfaceName() const {
    return k_interface;
}

QQmlListProperty<FileChooserRequest> FileChooserPortal::requests() {
    return { this, this, &FileChooserPortal::requestCount, &FileChooserPortal::requestAt };
}

void FileChooserPortal::add(FileChooserRequest::Action action, const QDBusObjectPath& handle, const QString& appId,
    const QString& title, const QVariantMap& options, const QDBusMessage& call) {
    call.setDelayedReply(true);

    auto* request = new FileChooserRequest(action, appId, title, options, call, handle, this);

    // The caller owns the handle and may withdraw the dialog through it.
    auto bus = QDBusConnection::sessionBus();
    new RequestAdaptor(request); // NOLINT(cppcoreguidelines-owning-memory) parented to the request
    if (!bus.registerObject(handle.path(), request, QDBusConnection::ExportAdaptors))
        qCWarning(lcFileChooser) << "Failed to export request handle" << handle.path();

    connect(request, &FileChooserRequest::finished, this, [this, request] {
        m_requests.removeOne(request);
        emit requestsChanged();
    });

    m_requests.append(request);
    emit requestsChanged();
    qCInfo(lcFileChooser) << "Chooser requested by" << (appId.isEmpty() ? u"an application"_s : appId);
}

qsizetype FileChooserPortal::requestCount(QQmlListProperty<FileChooserRequest>* list) {
    return static_cast<FileChooserPortal*>(list->object)->m_requests.size();
}

FileChooserRequest* FileChooserPortal::requestAt(QQmlListProperty<FileChooserRequest>* list, qsizetype index) {
    return static_cast<FileChooserPortal*>(list->object)->m_requests.at(index);
}

RequestAdaptor::RequestAdaptor(FileChooserRequest* request) : QDBusAbstractAdaptor(request), m_request(request) {}

void RequestAdaptor::Close() {
    m_request->close();
}

FileChooserAdaptor::FileChooserAdaptor(FileChooserPortal* portal, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_portal(portal) {}

uint FileChooserAdaptor::version() {
    return k_version;
}

void FileChooserAdaptor::OpenFile(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
    const QString& title, const QVariantMap& options, const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(FileChooserRequest::Action::Open, handle, appId, title, options, message);
}

void FileChooserAdaptor::SaveFile(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
    const QString& title, const QVariantMap& options, const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(FileChooserRequest::Action::Save, handle, appId, title, options, message);
}

void FileChooserAdaptor::SaveFiles(const QDBusObjectPath& handle, const QString& appId, const QString& parentWindow,
    const QString& title, const QVariantMap& options, const QDBusMessage& message) {
    Q_UNUSED(parentWindow)
    m_portal->add(FileChooserRequest::Action::SaveMultiple, handle, appId, title, options, message);
}

} // namespace hyprstack::portals
