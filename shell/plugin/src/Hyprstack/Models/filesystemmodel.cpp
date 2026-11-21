#include "filesystemmodel.hpp"

#include <qdirlisting.h>
#include <qtconcurrentrun.h>

#include <algorithm>
#include <utility>

namespace hyprstack::models {

using Qt::StringLiterals::operator""_s;
using Qt::StringLiterals::operator""_ba;

FileSystemEntry::FileSystemEntry(QFileInfo info, bool isDirectory, std::optional<Metadata> metadata,
    QString relativePath, QObject* parent)
    : QObject(parent)
    , m_fileInfo(std::move(info))
    , m_path(m_fileInfo.filePath())
    , m_relativePath(std::move(relativePath))
    , m_isDirectory(isDirectory)
    , m_metadata(std::move(metadata))
    , m_isImageInitialised(false)
    , m_mimeTypeInitialised(false) {}

QString FileSystemEntry::path() const {
    return m_path;
};

QString FileSystemEntry::relativePath() const {
    return m_relativePath;
};

QString FileSystemEntry::name() const {
    return m_fileInfo.fileName();
};

QString FileSystemEntry::baseName() const {
    return m_fileInfo.baseName();
};

QString FileSystemEntry::parentDir() const {
    return m_fileInfo.absolutePath();
};

QString FileSystemEntry::suffix() const {
    return m_fileInfo.suffix();
};

qint64 FileSystemEntry::size() const {
    return m_metadata ? m_metadata->size : m_fileInfo.size();
};

QDateTime FileSystemEntry::modified() const {
    return m_metadata ? m_metadata->modified : m_fileInfo.lastModified();
}

bool FileSystemEntry::updateInfo(QFileInfo info, bool isDirectory, std::optional<Metadata> metadata) {
    if (!metadata && m_isDirectory == isDirectory) return false;
    const bool changed = m_isDirectory != isDirectory
        || (metadata && m_metadata != metadata);
    m_fileInfo = std::move(info);
    m_isDirectory = isDirectory;
    m_metadata = std::move(metadata);
    if (changed) {
        m_isImageInitialised = false;
        m_mimeTypeInitialised = false;
        emit metadataChanged();
    }
    return changed;
}

bool FileSystemEntry::isDir() const {
    return m_isDirectory;
};

bool FileSystemEntry::isImage() const {
    if (m_isDirectory) return false;
    if (!m_isImageInitialised) {
        const QImageReader reader(m_path);
        m_isImage = reader.canRead();
        m_isImageInitialised = true;
    }
    return m_isImage;
}

QString FileSystemEntry::mimeType() const {
    if (!m_mimeTypeInitialised) {
        static const QMimeDatabase k_db;
        m_mimeType = k_db.mimeTypeForFile(m_path).name();
        m_mimeTypeInitialised = true;
    }
    return m_mimeType;
}

void FileSystemEntry::updateRelativePath(const QDir& dir) {
    const auto relPath = dir.relativeFilePath(m_path);
    if (m_relativePath != relPath) {
        m_relativePath = relPath;
        emit relativePathChanged();
    }
}

FileSystemModel::FileSystemModel(QObject* parent)
    : QAbstractListModel(parent)
    , m_recursive(false)
    , m_watchChanges(true)
    , m_showHidden(false)
    , m_filter(Filter::NoFilter) {
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
        [this](const QString& dir) { updateEntriesForDir(dir); });
}

FileSystemModel::~FileSystemModel() {
    m_scan.cancel();
}

int FileSystemModel::rowCount(const QModelIndex& parent) const {
    if (parent != QModelIndex()) {
        return 0;
    }
    return static_cast<int>(m_entries.size());
}

QVariant FileSystemModel::data(const QModelIndex& index, int role) const {
    if (role != Qt::UserRole || !index.isValid() || index.row() >= m_entries.size()) {
        return {};
    }
    return QVariant::fromValue(m_entries.at(index.row()));
}

QHash<int, QByteArray> FileSystemModel::roleNames() const {
    return { { Qt::UserRole, "modelData"_ba } };
}

QString FileSystemModel::path() const {
    return m_path;
}

void FileSystemModel::setPath(const QString& path) {
    if (m_path == path) {
        return;
    }

    m_path = path;
    emit pathChanged();

    m_dir.setPath(m_path);

    for (const auto& entry : std::as_const(m_entries)) {
        entry->updateRelativePath(m_dir);
    }

    update();
}

bool FileSystemModel::recursive() const {
    return m_recursive;
}

void FileSystemModel::setRecursive(bool recursive) {
    if (m_recursive == recursive) {
        return;
    }

    m_recursive = recursive;
    emit recursiveChanged();

    update();
}

bool FileSystemModel::watchChanges() const {
    return m_watchChanges;
}

void FileSystemModel::setWatchChanges(bool watchChanges) {
    if (m_watchChanges == watchChanges) {
        return;
    }

    m_watchChanges = watchChanges;
    emit watchChangesChanged();

    update();
}

bool FileSystemModel::showHidden() const {
    return m_showHidden;
}

void FileSystemModel::setShowHidden(bool showHidden) {
    if (m_showHidden == showHidden) {
        return;
    }

    m_showHidden = showHidden;
    emit showHiddenChanged();

    update();
}

bool FileSystemModel::sortReverse() const {
    return m_sortReverse;
}

void FileSystemModel::setSortReverse(bool sortReverse) {
    if (m_sortReverse == sortReverse) {
        return;
    }

    m_sortReverse = sortReverse;
    emit sortReverseChanged();
    updateOrder();
}

bool FileSystemModel::foldersFirst() const { return m_foldersFirst; }

void FileSystemModel::setFoldersFirst(bool foldersFirst) {
    if (m_foldersFirst == foldersFirst) return;
    m_foldersFirst = foldersFirst;
    emit foldersFirstChanged();
    updateOrder();
}

bool FileSystemModel::loading() const { return m_scanning; }

void FileSystemModel::updateOrder() {
    if (m_scanning || m_sortPending)
        m_sortPending = true;
    else
        sortEntries();
}

FileSystemModel::SortBy FileSystemModel::sortBy() const { return m_sortBy; }

static bool needsFileMetadata(FileSystemModel::SortBy sortBy) {
    return sortBy == FileSystemModel::SortBy::Modified || sortBy == FileSystemModel::SortBy::Size;
}

void FileSystemModel::setSortBy(SortBy sortBy) {
    if (sortBy > SortBy::Type || m_sortBy == sortBy) return;
    const bool rescan = needsFileMetadata(sortBy) || m_scanning;
    m_sortBy = sortBy;
    m_sortPending = rescan;
    emit sortByChanged();
    if (rescan) {
        updateEntries();
    } else {
        sortEntries();
    }
}

void FileSystemModel::refresh() {
    updateEntries(true);
}

void FileSystemModel::sortEntries() {
    if (m_entries.isEmpty()) return;
    const auto previous = m_entries;
    emit layoutAboutToBeChanged({}, QAbstractItemModel::VerticalSortHint);
    const auto persistent = persistentIndexList();
    std::ranges::sort(m_entries, [this](const auto* a, const auto* b) { return compareEntries(a, b); });
    QHash<FileSystemEntry*, int> rows;
    for (int i = 0; i < m_entries.size(); ++i) rows.insert(m_entries[i], i);
    QModelIndexList next;
    for (const auto& old : persistent) next.append(index(rows.value(previous[old.row()]), old.column()));
    changePersistentIndexList(persistent, next);
    emit layoutChanged({}, QAbstractItemModel::VerticalSortHint);
    emit entriesChanged();
}

FileSystemModel::Filter FileSystemModel::filter() const {
    return m_filter;
}

void FileSystemModel::setFilter(Filter filter) {
    if (m_filter == filter) {
        return;
    }

    m_filter = filter;
    emit filterChanged();

    updateEntries();
}

QStringList FileSystemModel::nameFilters() const {
    return m_nameFilters;
}

void FileSystemModel::setNameFilters(const QStringList& nameFilters) {
    if (m_nameFilters == nameFilters) {
        return;
    }

    m_nameFilters = nameFilters;
    emit nameFiltersChanged();

    updateEntries();
}

QQmlListProperty<FileSystemEntry> FileSystemModel::entries() {
    return { this, &m_entries };
}

void FileSystemModel::update() {
    const auto watched = m_watcher.directories();
    if (!watched.isEmpty())
        m_watcher.removePaths(watched);
    if (m_watchChanges && !m_path.isEmpty())
        m_watcher.addPath(m_path);
    updateEntries();
}

void FileSystemModel::updateEntries(bool refreshMetadata) {
    const bool wasLoading = m_scanning;
    ++m_generation;
    m_scan.cancel();
    m_scanning = false;
    m_pendingDirs.clear();
    if (!m_path.isEmpty()) {
        updateEntriesForDir(m_path, refreshMetadata);
    } else {
        if (wasLoading) emit loadingChanged();
        if (!m_entries.isEmpty()) {
            beginResetModel();
            qDeleteAll(m_entries);
            m_entries.clear();
            endResetModel();
            emit entriesChanged();
        }
    }
}

void FileSystemModel::updateEntriesForDir(const QString& dir, bool refreshMetadata) {
    if (m_scanning) {
        // A parent change and a child change can overlap. Apply one snapshot
        // at a time and scan again for events received while it was in flight.
        if (dir == m_path)
            m_pendingDirs.clear();
        if (!m_pendingDirs.contains(m_path))
            m_pendingDirs.insert(dir);
        return;
    }

    m_scanning = true;
    const bool recursive = m_recursive;
    const bool collectDirs = recursive && m_watchChanges;
    const auto filter = m_filter;
    const auto names = m_nameFilters;
    const bool hidden = m_showHidden;
    const bool loadMetadata = refreshMetadata || needsFileMetadata(m_sortBy);
    m_scan = QtConcurrent::run([=](QPromise<ScanResult>& promise) {
        using Flag = QDirListing::IteratorFlag;
        const auto filters = filtersFor(filter, names);
        auto flags = QDirListing::IteratorFlags(Flag::ResolveSymlinks);
        if (hidden) flags |= Flag::IncludeHidden;
        if (recursive) flags |= Flag::Recursive;
        const bool filesOnly = filter == Filter::Files || filter == Filter::Images;
        if (!collectDirs && filesOnly) flags |= Flag::FilesOnly;
        if (filter == Filter::Dirs) flags |= Flag::DirsOnly;
        ScanResult result;
        for (const auto& entry : QDirListing(dir, collectDirs ? QStringList{} : filters.nameFilters, flags)) {
            if (promise.isCanceled()) return;
            const bool isDirectory = entry.isDir();
            if (!isDirectory && !entry.isFile()) continue;
            const auto path = entry.filePath();
            if (collectDirs && isDirectory && !entry.isSymLink())
                result.directories.insert(path);
            if (isDirectory && filesOnly) continue;
            if (collectDirs && !filters.nameFilters.isEmpty() && !QDir::match(filters.nameFilters, entry.fileName()))
                continue;
            if (filters.filterFn && !filters.filterFn(path)) continue;
            auto info = entry.fileInfo();
            std::optional<FileSystemEntry::Metadata> metadata;
            if (loadMetadata)
                metadata.emplace(info.size(), info.lastModified());
            result.entries.insert(path, {std::move(info), isDirectory, std::move(metadata)});
        }
        if (!promise.isCanceled())
            promise.addResult(std::move(result));
    });

    m_scan.then(this, [this, dir, generation = m_generation](ScanResult result) {
        if (generation != m_generation)
            return;
        if (!result.directories.isEmpty()) {
            for (const auto& watched : m_watcher.directories())
                result.directories.remove(watched);
            const auto paths = result.directories.values();
            // Cover changes between discovering a new subdirectory and adding its watch.
            if (!paths.isEmpty() && m_watcher.addPaths(paths).size() < paths.size())
                m_pendingDirs.insert(dir);
        }

        const bool isRoot = dir == m_path;
        const QString prefix = dir.endsWith(u'/') ? dir : dir + u'/';
        QSet<QString> removed;
        bool resort = std::exchange(m_sortPending, false);
        for (auto* entry : std::as_const(m_entries)) {
            const auto path = entry->path();
            if (!isRoot && !path.startsWith(prefix)) continue;
            const auto found = result.entries.find(path);
            if (found == result.entries.end()) {
                removed.insert(path);
            } else {
                const bool typeChanged = entry->isDir() != found->isDirectory;
                const bool updated = entry->updateInfo(
                    std::move(found->info), found->isDirectory, std::move(found->metadata));
                if (generation != m_generation) return;
                resort = resort || typeChanged || (updated && needsFileMetadata(m_sortBy));
                result.entries.erase(found);
            }
        }
        if (resort || !removed.isEmpty() || !result.entries.isEmpty())
            applyChanges(removed, std::move(result.entries), resort);

        // Model signals can synchronously navigate to another directory.
        if (generation != m_generation)
            return;
        m_scanning = false;
        if (!m_pendingDirs.isEmpty()) {
            const auto next = *m_pendingDirs.constBegin();
            m_pendingDirs.remove(next);
            updateEntriesForDir(next);
        } else emit loadingChanged();
    });
    emit loadingChanged();
}

FileSystemModel::ScanFilters FileSystemModel::filtersFor(
    Filter filter, const QStringList& nameFilters) {
    ScanFilters filters;
    filters.nameFilters = nameFilters;

    if (filter == Filter::Images) {
        const auto formats = QImageReader::supportedImageFormats();
        for (const auto& format : formats)
            filters.nameFilters << u"*."_s + QString::fromUtf8(format);

        filters.filterFn = [](const QString& path) {
            return QImageReader(path).canRead();
        };
    }

    return filters;
}

void FileSystemModel::applyChanges(const QSet<QString>& removedPaths, ScannedEntries addedEntries, bool resort) {
    QList<int> removedIndices;
    for (int i = 0; i < m_entries.size(); ++i) {
        if (removedPaths.contains(m_entries[i]->path())) {
            removedIndices << i;
        }
    }
    std::ranges::sort(removedIndices, std::greater<>());

    // Batch remove old entries
    int start = -1;
    int end = -1;
    for (const int idx : std::as_const(removedIndices)) {
        if (start == -1) {
            start = idx;
            end = idx;
        } else if (idx == end - 1) {
            end = idx;
        } else {
            beginRemoveRows(QModelIndex(), end, start);
            for (int i = start; i >= end; --i) {
                m_entries.takeAt(i)->deleteLater();
            }
            endRemoveRows();

            start = idx;
            end = idx;
        }
    }
    if (start != -1) {
        beginRemoveRows(QModelIndex(), end, start);
        for (int i = start; i >= end; --i) {
            m_entries.takeAt(i)->deleteLater();
        }
        endRemoveRows();
    }

    // Rows from the previous directory have no metadata in this scan.
    // Remove them before sorting with keys from the new snapshot.
    if (resort) {
        const auto generation = m_generation;
        sortEntries();
        if (generation != m_generation) return;
    }

    // Create new entries
    QList<FileSystemEntry*> newEntries;
    newEntries.reserve(addedEntries.size());
    for (auto [path, entry] : addedEntries.asKeyValueRange())
        newEntries << new FileSystemEntry(std::move(entry.info), entry.isDirectory, std::move(entry.metadata),
            m_dir.relativeFilePath(path), this);
    std::ranges::sort(newEntries, [this](const FileSystemEntry* a, const FileSystemEntry* b) {
        return compareEntries(a, b);
    });

    // Batch insert new entries (each run lands contiguously before m_entries[row])
    int i = 0;
    while (i < newEntries.size()) {
        const auto it = std::ranges::lower_bound(
            m_entries, newEntries[i], [this](const FileSystemEntry* a, const FileSystemEntry* b) {
                return compareEntries(a, b);
            });
        const auto row = static_cast<int>(it - m_entries.begin());

        // Extend the run while the next new entry still sorts before the existing element at row
        int j = i + 1;
        while (j < newEntries.size() && (row >= m_entries.size() || compareEntries(newEntries[j], m_entries[row]))) {
            ++j;
        }

        beginInsertRows(QModelIndex(), row, row + (j - i) - 1);
        for (int k = i; k < j; ++k) {
            m_entries.insert(row + (k - i), newEntries[k]);
        }
        endInsertRows();

        i = j;
    }

    emit entriesChanged();
}

bool FileSystemModel::compareEntries(const FileSystemEntry* a, const FileSystemEntry* b) const {
    if (m_foldersFirst && a->isDir() != b->isDir()) {
        return a->isDir();
    }
    int cmp = 0;
    switch (m_sortBy) {
    case SortBy::Modified: {
        const auto modifiedA = a->modified();
        const auto modifiedB = b->modified();
        cmp = modifiedA < modifiedB ? -1 : modifiedA > modifiedB ? 1 : 0;
        break;
    }
    case SortBy::Size: {
        const auto sizeA = a->isDir() ? 0 : a->size();
        const auto sizeB = b->isDir() ? 0 : b->size();
        cmp = sizeA < sizeB ? -1 : sizeA > sizeB ? 1 : 0;
        break;
    }
    case SortBy::Type:
        cmp = a->suffix().toCaseFolded().localeAwareCompare(b->suffix().toCaseFolded());
        break;
    case SortBy::Name: break;
    }
    if (cmp == 0) cmp = a->relativePath().localeAwareCompare(b->relativePath());
    return m_sortReverse ? cmp > 0 : cmp < 0;
}

} // namespace hyprstack::models
