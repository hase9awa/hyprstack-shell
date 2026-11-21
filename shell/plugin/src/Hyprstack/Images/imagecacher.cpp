#include "imagecacher.hpp"

#include <qcryptographichash.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qimage.h>
#include <qimagereader.h>
#include <qdatetime.h>
#include <qloggingcategory.h>
#include <qpainter.h>
#include <qsavefile.h>

#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcCacher, "hyprstack.images.cacher", QtInfoMsg)

} // namespace

namespace hyprstack::images {

using Qt::StringLiterals::operator""_s;

namespace {

QString sha256sum(const QString& path) {
    const QFileInfo info(path);
    if (!info.isFile()) {
        return {};
    }
    // Hash file identity and metadata instead of rereading the entire wallpaper
    // every time a thumbnail is requested or its dimensions change.
    const auto identity = info.canonicalFilePath().toUtf8() + '\0' + QByteArray::number(info.size()) + '\0' +
        QByteArray::number(info.lastModified().toMSecsSinceEpoch());
    return QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex());
}

QString fillSuffix(ImageCacher::FillMode fillMode) {
    switch (fillMode) {
    case ImageCacher::FillMode::Crop:
        return u"crop"_s;
    case ImageCacher::FillMode::Fit:
        return u"fit"_s;
    default:
        return u"stretch"_s;
    }
}

} // namespace

const QString& ImageCacher::cacheDir() {
    static const QString k_dir = [] {
        QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
        if (cache.isEmpty())
            cache = QDir::homePath() + u"/.cache"_s;
        return cache + u"/hyprstack/imagecache"_s;
    }();
    return k_dir;
}

QString ImageCacher::cachePathFor(const QString& sourcePath, const QSize& size, FillMode fillMode) {
    const QString sha = sha256sum(sourcePath);
    if (sha.isEmpty())
        return {};

    const QString filename = u"%1@%2x%3-%4.png"_s.arg(
        sha, QString::number(size.width()), QString::number(size.height()), fillSuffix(fillMode));

    return cacheDir() + u'/' + filename;
}

QImage ImageCacher::load(const QString& sourcePath, const QSize& size, FillMode fillMode) {
    if (!size.isValid() || size.isEmpty() || size.width() > 16384 || size.height() > 16384 ||
        static_cast<qint64>(size.width()) * size.height() > 64 * 1024 * 1024)
        return {};
    const auto cachePath = cachePathFor(sourcePath, size, fillMode);
    if (QFile::exists(cachePath)) {
        QImageReader cached(cachePath);
        auto image = cached.read();
        if (!image.isNull() && image.size() == size)
            return image;
    }
    Qt::AspectRatioMode scaleMode = Qt::IgnoreAspectRatio;
    switch (fillMode) {
    case FillMode::Crop:
        scaleMode = Qt::KeepAspectRatioByExpanding;
        break;
    case FillMode::Fit:
        scaleMode = Qt::KeepAspectRatio;
        break;
    case FillMode::Stretch:
        scaleMode = Qt::IgnoreAspectRatio;
        break;
    }

    QImageReader reader(sourcePath);
    reader.setAutoTransform(true);
    const auto sourceSize = reader.size();
    if (sourceSize.isValid()) {
        // QImageReader scales in file coordinates before applying EXIF orientation.
        const auto target = reader.transformation().testFlag(QImageIOHandler::TransformationRotate90)
            ? size.transposed() : size;
        auto decodedSize = sourceSize.scaled(target, scaleMode);
        if (decodedSize.width() > 16384 || decodedSize.height() > 16384 ||
            static_cast<qint64>(decodedSize.width()) * decodedSize.height() > 64 * 1024 * 1024)
            decodedSize = sourceSize.scaled(target, Qt::KeepAspectRatio);
        reader.setScaledSize(decodedSize.expandedTo(QSize(1, 1)));
    }
    QImage image = reader.read();

    if (image.isNull()) {
        qCWarning(lcCacher).noquote() << "Failed to scale" << sourcePath;
        return {};
    }

    // JPEG and other scaled decoders can already return exactly the requested
    // bitmap. Only allocate a second frame for cropping or padding.
    if (image.size() != size) {
        QImage canvas(size, QImage::Format_ARGB32);
        if (canvas.isNull())
            return {};
        canvas.fill(Qt::transparent);
        QPainter painter(&canvas);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        if (fillMode == FillMode::Crop) {
            const auto factor = std::min(static_cast<qreal>(image.width()) / size.width(),
                                         static_cast<qreal>(image.height()) / size.height());
            const auto width = size.width() * factor;
            const auto height = size.height() * factor;
            painter.drawImage(QRectF(QPointF(0, 0), QSizeF(size)), image,
                              QRectF((image.width() - width) / 2, (image.height() - height) / 2, width, height));
        } else {
            const auto dimensions = image.size().scaled(size, scaleMode);
            painter.drawImage(QRect(QPoint((size.width() - dimensions.width()) / 2,
                                          (size.height() - dimensions.height()) / 2), dimensions), image);
        }
        painter.end();
        image = std::move(canvas);
    }

    if (cachePath.isEmpty())
        return image;

    const QString parent = QFileInfo(cachePath).absolutePath();
    if (!QDir().mkpath(parent)) {
        qCWarning(lcCacher).noquote() << "Failed to create cache dir" << parent;
        return image;
    }

    QSaveFile saveFile(cachePath);
    if (!saveFile.open(QIODevice::WriteOnly) || !image.save(&saveFile, "PNG") || !saveFile.commit()) {
        qCWarning(
            lcCacher, "Failed to save to %s: %s", qUtf8Printable(cachePath), qUtf8Printable(saveFile.errorString()));
        return image;
    }

    qCDebug(lcCacher).noquote() << "Saved to" << cachePath;
    return image;
}

} // namespace hyprstack::images
