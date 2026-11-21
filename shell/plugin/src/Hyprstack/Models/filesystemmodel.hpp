#pragma once

#include <qabstractitemmodel.h>
#include <qdatetime.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qfilesystemwatcher.h>
#include <qfuture.h>
#include <qimagereader.h>
#include <qmimedatabase.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>

#include <optional>

namespace hyprstack::models {

class FileSystemEntry : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("FileSystemEntry instances can only be retrieved from a FileSystemModel")

    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString relativePath READ relativePath NOTIFY relativePathChanged)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString baseName READ baseName CONSTANT)
    Q_PROPERTY(QString parentDir READ parentDir CONSTANT)
    Q_PROPERTY(QString suffix READ suffix CONSTANT)
    Q_PROPERTY(qint64 size READ size NOTIFY metadataChanged)
    Q_PROPERTY(QDateTime modified READ modified NOTIFY metadataChanged)
    Q_PROPERTY(bool isDir READ isDir NOTIFY metadataChanged)
    Q_PROPERTY(bool isImage READ isImage NOTIFY metadataChanged)
    Q_PROPERTY(QString mimeType READ mimeType NOTIFY metadataChanged)

public:
    struct Metadata {
        qint64 size;
        QDateTime modified;
        bool operator==(const Metadata&) const = default;
    };

    explicit FileSystemEntry(QFileInfo info, bool isDirectory, std::optional<Metadata> metadata,
        QString relativePath, QObject* parent = nullptr);

    [[nodiscard]] QString path() const;
    [[nodiscard]] QString relativePath() const;
    [[nodiscard]] QString name() const;
    [[nodiscard]] QString baseName() const;
    [[nodiscard]] QString parentDir() const;
    [[nodiscard]] QString suffix() const;
    [[nodiscard]] qint64 size() const;
    [[nodiscard]] QDateTime modified() const;
    [[nodiscard]] bool isDir() const;
    [[nodiscard]] bool isImage() const;
    [[nodiscard]] QString mimeType() const;

    void updateRelativePath(const QDir& dir);
    bool updateInfo(QFileInfo info, bool isDirectory, std::optional<Metadata> metadata);

signals:
    void relativePathChanged();
    void metadataChanged();

private:
    QFileInfo m_fileInfo;

    const QString m_path;
    QString m_relativePath;
    bool m_isDirectory;
    std::optional<Metadata> m_metadata;

    mutable bool m_isImage;
    mutable bool m_isImageInitialised;

    mutable QString m_mimeType;
    mutable bool m_mimeTypeInitialised;
};

class FileSystemModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool recursive READ recursive WRITE setRecursive NOTIFY recursiveChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges NOTIFY watchChangesChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(bool sortReverse READ sortReverse WRITE setSortReverse NOTIFY sortReverseChanged)
    Q_PROPERTY(SortBy sortBy READ sortBy WRITE setSortBy NOTIFY sortByChanged)
    Q_PROPERTY(bool foldersFirst READ foldersFirst WRITE setFoldersFirst NOTIFY foldersFirstChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(Filter filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QStringList nameFilters READ nameFilters WRITE setNameFilters NOTIFY nameFiltersChanged)

    Q_PROPERTY(QQmlListProperty<hyprstack::models::FileSystemEntry> entries READ entries NOTIFY entriesChanged)

public:
    enum class Filter : quint8 {
        NoFilter,
        Images,
        Files,
        Dirs,
    };
    Q_ENUM(Filter)

    enum class SortBy : quint8 { Name, Modified, Size, Type };
    Q_ENUM(SortBy)

    explicit FileSystemModel(QObject* parent = nullptr);
    ~FileSystemModel() override;

    [[nodiscard]] int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QString path() const;
    void setPath(const QString& path);

    [[nodiscard]] bool recursive() const;
    void setRecursive(bool recursive);

    [[nodiscard]] bool watchChanges() const;
    void setWatchChanges(bool watchChanges);

    [[nodiscard]] bool showHidden() const;
    void setShowHidden(bool showHidden);

    [[nodiscard]] bool sortReverse() const;
    void setSortReverse(bool sortReverse);
    [[nodiscard]] SortBy sortBy() const;
    void setSortBy(SortBy sortBy);
    [[nodiscard]] bool foldersFirst() const;
    void setFoldersFirst(bool foldersFirst);
    [[nodiscard]] bool loading() const;
    Q_INVOKABLE void refresh();

    [[nodiscard]] Filter filter() const;
    void setFilter(Filter filter);

    [[nodiscard]] QStringList nameFilters() const;
    void setNameFilters(const QStringList& nameFilters);

    [[nodiscard]] QQmlListProperty<FileSystemEntry> entries();

signals:
    void pathChanged();
    void recursiveChanged();
    void watchChangesChanged();
    void showHiddenChanged();
    void sortReverseChanged();
    void sortByChanged();
    void foldersFirstChanged();
    void loadingChanged();
    void filterChanged();
    void nameFiltersChanged();
    void entriesChanged();

private:
    struct ScannedEntry {
        QFileInfo info;
        bool isDirectory;
        std::optional<FileSystemEntry::Metadata> metadata;
    };
    using ScannedEntries = QHash<QString, ScannedEntry>;

    struct ScanResult {
        ScannedEntries entries;
        QSet<QString> directories;
    };

    struct ScanFilters {
        QStringList nameFilters;
        std::function<bool(const QString&)> filterFn = nullptr;
    };

    QDir m_dir;
    QFileSystemWatcher m_watcher;
    QList<FileSystemEntry*> m_entries;
    QFuture<ScanResult> m_scan;
    quint64 m_generation = 0;
    bool m_scanning = false;
    bool m_sortPending = false;
    QSet<QString> m_pendingDirs;

    QString m_path;
    bool m_recursive;
    bool m_watchChanges;
    bool m_showHidden;
    bool m_sortReverse = false;
    bool m_foldersFirst = true;
    SortBy m_sortBy = SortBy::Name;
    Filter m_filter;
    QStringList m_nameFilters;

    void update();
    void updateEntries(bool refreshMetadata = false);
    void updateEntriesForDir(const QString& dir, bool refreshMetadata = false);
    [[nodiscard]] static ScanFilters filtersFor(Filter filter, const QStringList& nameFilters);
    void applyChanges(const QSet<QString>& removedPaths, ScannedEntries addedEntries, bool resort);
    void sortEntries();
    void updateOrder();
    [[nodiscard]] bool compareEntries(const FileSystemEntry* a, const FileSystemEntry* b) const;
};

} // namespace hyprstack::models
