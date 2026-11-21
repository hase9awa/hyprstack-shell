#include "appdb.hpp"

#include <qloggingcategory.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qsqldatabase.h>
#include <qsqlerror.h>
#include <qsqlquery.h>
#include <quuid.h>

#include <algorithm>

namespace {

Q_LOGGING_CATEGORY(lcAppDb, "hyprstack.appdb", QtInfoMsg)

} // namespace

namespace hyprstack::models {

using Qt::StringLiterals::operator""_s;

AppEntry::AppEntry(QObject* entry, unsigned int frequency, QObject* parent)
    : QObject(parent)
    , m_entry(entry)
    , m_frequency(frequency) {
    const auto* mo = m_entry->metaObject();
    const auto* tmo = &AppEntry::staticMetaObject;

    for (const auto& prop :
        { "name", "comment", "execString", "startupClass", "genericName", "categories", "keywords" }) {
        const auto metaProp = mo->property(mo->indexOfProperty(prop));
        const auto thisMetaProp = tmo->property(tmo->indexOfProperty(prop));
        QObject::connect(m_entry, metaProp.notifySignal(), this, thisMetaProp.notifySignal());
    }

    QObject::connect(m_entry, &QObject::destroyed, this, [this] {
        m_entry = nullptr;
        deleteLater();
    });
}

QObject* AppEntry::entry() const {
    return m_entry;
}

quint32 AppEntry::frequency() const {
    return m_frequency;
}

void AppEntry::setFrequency(unsigned int frequency) {
    if (m_frequency != frequency) {
        m_frequency = frequency;
        emit frequencyChanged();
    }
}

void AppEntry::incrementFrequency() {
    m_frequency++;
    emit frequencyChanged();
}

QString AppEntry::id() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("id").toString();
}

QString AppEntry::name() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("name").toString();
}

QString AppEntry::comment() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("comment").toString();
}

QString AppEntry::execString() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("execString").toString();
}

QString AppEntry::startupClass() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("startupClass").toString();
}

QString AppEntry::genericName() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("genericName").toString();
}

QString AppEntry::categories() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("categories").toStringList().join(u" "_s);
}

QString AppEntry::keywords() const {
    if (!m_entry) {
        return {};
    }
    return m_entry->property("keywords").toStringList().join(u" "_s);
}

AppDb::AppDb(QObject* parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
    , m_uuid(QUuid::createUuid().toString()) {
    m_timer->setSingleShot(true);
    m_timer->setInterval(300);
    QObject::connect(m_timer, &QTimer::timeout, this, &AppDb::updateApps);

    auto db = QSqlDatabase::addDatabase(u"QSQLITE"_s, m_uuid);
    db.setDatabaseName(u":memory:"_s);
    if (db.open()) {
        QSqlQuery query(db);
        query.exec(u"CREATE TABLE IF NOT EXISTS frequencies (id TEXT PRIMARY KEY, frequency INTEGER)"_s);
    } else {
        qCWarning(lcAppDb) << "SQLite driver unavailable; application usage history is disabled:" << db.lastError().text();
    }
}

AppDb::~AppDb() {
    QSqlDatabase::removeDatabase(m_uuid);
}

QString AppDb::uuid() const {
    return m_uuid;
}

QString AppDb::path() const {
    return m_path;
}

void AppDb::setPath(const QString& path) {
    const auto newPath = path.isEmpty() ? u":memory:"_s : path;

    if (m_path == newPath) {
        return;
    }

    m_path = newPath;
    emit pathChanged();

    auto db = QSqlDatabase::database(m_uuid, false);
    db.close();
    const bool directoryReady = newPath == u":memory:"_s || QDir().mkpath(QFileInfo(newPath).absolutePath());
    db.setDatabaseName(newPath);
    if (!directoryReady || !db.open()) {
        qCWarning(lcAppDb) << "Cannot open application history:" << newPath << db.lastError().text();
        db.close();
        db.setDatabaseName(u":memory:"_s);
        if (!db.open()) {
            updateAppFrequencies();
            return;
        }
    }

    QSqlQuery query(db);
    query.exec(u"CREATE TABLE IF NOT EXISTS frequencies (id TEXT PRIMARY KEY, frequency INTEGER)"_s);

    updateAppFrequencies();
}

QObjectList AppDb::entries() const {
    QObjectList result;
    for (const auto& entry : m_entries)
        if (entry) result.append(entry.data());
    return result;
}

void AppDb::setEntries(const QObjectList& entries) {
    if (std::ranges::equal(m_entries, entries, {}, &QPointer<QObject>::data)) {
        return;
    }

    m_entries = QList<QPointer<QObject>>(entries.cbegin(), entries.cend());
    emit entriesChanged();

    m_timer->start();
}

QStringList AppDb::favouriteApps() const {
    return m_favouriteApps;
}

void AppDb::setFavouriteApps(const QStringList& favApps) {
    if (m_favouriteApps == favApps) {
        return;
    }

    m_favouriteApps = favApps;
    emit favouriteAppsChanged();
    m_favouriteAppsRegex.clear();
    m_favouriteAppsRegex.reserve(m_favouriteApps.size());
    for (const QString& item : std::as_const(m_favouriteApps)) {
        const QRegularExpression re(regexifyString(item));
        if (re.isValid()) {
            m_favouriteAppsRegex << re;
        } else {
            qCWarning(lcAppDb) << "setFavouriteApps: regular expression is not valid:" << re.pattern();
        }
    }

    sortApps();
}

QString AppDb::regexifyString(const QString& original) {
    if (original.startsWith(u'^') && original.endsWith(u'$'))
        return original;

    const QString escaped = QRegularExpression::escape(original);
    return u"^%1$"_s.arg(escaped);
}

QQmlListProperty<AppEntry> AppDb::apps() {
    return { this, &m_sortedApps };
}

void AppDb::incrementFrequency(const QString& id) {
    const auto db = QSqlDatabase::database(m_uuid, false);
    if (db.isOpen()) {
        QSqlQuery query(db);
        query.prepare(u"INSERT INTO frequencies (id, frequency) "
                  "VALUES (:id, 1) "
                  "ON CONFLICT (id) DO UPDATE SET frequency = frequency + 1"_s);
        query.bindValue(u":id"_s, id);
        query.exec();
    }

    auto* app = m_apps.value(id);
    if (app) {
        app->incrementFrequency();
        sortApps();
    } else {
        qCWarning(lcAppDb) << "incrementFrequency: could not find app with id" << id;
    }
}

void AppDb::sortApps() {
    auto sorted = m_apps.values();

    // Pre-compute favourite status to avoid repeated regex matching during sort
    QSet<QString> favSet;
    favSet.reserve(sorted.size());
    for (const auto* app : std::as_const(sorted)) {
        if (isFavourite(app))
            favSet.insert(app->id());
    }

    std::ranges::sort(sorted, [&favSet](AppEntry* a, AppEntry* b) {
        const bool aIsFav = favSet.contains(a->id());
        const bool bIsFav = favSet.contains(b->id());
        if (aIsFav != bIsFav)
            return aIsFav;
        if (a->frequency() != b->frequency())
            return a->frequency() > b->frequency();
        return a->name().localeAwareCompare(b->name()) < 0;
    });
    if (m_sortedApps != sorted) {
        m_sortedApps = std::move(sorted);
        emit appsChanged();
    }
}

bool AppDb::isFavourite(const AppEntry* app) const {
    const QString id = app->id();
    return std::ranges::any_of(m_favouriteAppsRegex, [&id](const QRegularExpression& re) {
        return re.match(id).hasMatch();
    });
}

QHash<QString, quint32> AppDb::readFrequencies() const {
    QHash<QString, quint32> frequencies;
    const auto db = QSqlDatabase::database(m_uuid, false);
    if (db.isOpen()) {
        QSqlQuery query(db);
        query.setForwardOnly(true);
        if (query.exec(u"SELECT id, frequency FROM frequencies"_s)) {
            while (query.next())
                frequencies.insert(query.value(0).toString(), query.value(1).toUInt());
        }
    }
    return frequencies;
}

void AppDb::updateAppFrequencies() {
    const auto frequencies = readFrequencies();
    for (auto* app : std::as_const(m_apps))
        app->setFrequency(frequencies.value(app->id()));
    sortApps();
}

void AppDb::updateApps() {
    bool dirty = false;
    QSet<QString> newIds;
    const auto frequencies = readFrequencies();
    for (const auto& entry : std::as_const(m_entries)) {
        if (!entry)
            continue;
        const auto id = entry->property("id").toString();
        newIds.insert(id);
        auto* previous = m_apps.value(id);
        if (!previous || previous->entry() != entry) {
            if (previous)
                previous->deleteLater();
            dirty = true;
            auto* const newEntry = new AppEntry(entry, frequencies.value(id), this);
            connect(newEntry, &AppEntry::nameChanged, this, &AppDb::sortApps);
            connect(newEntry, &QObject::destroyed, this, [id, newEntry, this] {
                if (m_apps.value(id) == newEntry) {
                    m_apps.remove(id);
                    sortApps();
                }
            });
            m_apps.insert(id, newEntry);
        }
    }

    for (auto it = m_apps.begin(); it != m_apps.end();) {
        if (!newIds.contains(it.key())) {
            dirty = true;
            it.value()->deleteLater();
            it = m_apps.erase(it);
        } else {
            ++it;
        }
    }

    if (dirty)
        sortApps();
}

} // namespace hyprstack::models
