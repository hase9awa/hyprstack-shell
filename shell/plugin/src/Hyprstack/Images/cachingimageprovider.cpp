#include "cachingimageprovider.hpp"

#include <qfileinfo.h>
#include <qimage.h>
#include <qimagereader.h>
#include <qloggingcategory.h>
#include <qrunnable.h>
#include <qthreadpool.h>

#include <atomic>
#include <limits>
#include <utility>

#include "imagecacher.hpp"

namespace {

Q_LOGGING_CATEGORY(lcCProv, "hyprstack.images.cacheprovider", QtInfoMsg)

} // namespace

namespace hyprstack::images {

using Qt::StringLiterals::operator""_s;

namespace {

class CachingImageResponse final : public QQuickImageResponse, public QRunnable {
public:
    CachingImageResponse(QString id, const QSize& requestedSize, ImageCacher::FillMode fillMode);

    [[nodiscard]] QQuickTextureFactory* textureFactory() const override;

    [[nodiscard]] QString errorString() const override;

    void run() override;
    void cancel() override { m_cancelled.store(true, std::memory_order_relaxed); }

private:
    void process();

    QString m_id;
    QSize m_requestedSize;
    ImageCacher::FillMode m_fillMode;
    std::atomic_bool m_cancelled = false;
    QImage m_image;
    QString m_error;
};

CachingImageResponse::CachingImageResponse(QString id, const QSize& requestedSize, ImageCacher::FillMode fillMode)
    : m_id(std::move(id))
    , m_requestedSize(requestedSize)
    , m_fillMode(fillMode) {
    setAutoDelete(false);
}

QQuickTextureFactory* CachingImageResponse::textureFactory() const {
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

QString CachingImageResponse::errorString() const {
    return m_error;
}

void CachingImageResponse::run() {
    if (!m_cancelled.load(std::memory_order_relaxed))
        process();
    emit finished();
}

void CachingImageResponse::process() {
    QString path = QString::fromUtf8(m_id.toUtf8().percentDecoded());
    if (!path.startsWith(u'/'))
        path.prepend(u'/');

    if (!QFileInfo::exists(path)) {
        m_error = u"Source file does not exist: "_s + path;
        qCWarning(lcCProv).noquote() << m_error;
        return;
    }

    QSize size = m_requestedSize;
    const bool needsW = size.width() <= 0;
    const bool needsH = size.height() <= 0;

    // If both dimensions are missing, return the original directly
    if (needsW && needsH) {
        qCDebug(lcCProv).noquote() << "Given source size is invalid, returning original:" << path;
        QImageReader reader(path);
        reader.setAutoTransform(true);
        m_image = reader.read();
        if (m_image.isNull()) {
            m_error = u"Failed to decode source: "_s + path;
            qCWarning(lcCProv).noquote() << m_error;
        }
        return;
    }

    // If one dimension is missing, derive it from the source aspect ratio
    if (needsW || needsH) {
        const QImageReader sourceReader(path);
        auto sourceSize = sourceReader.size();
        if (sourceReader.transformation().testFlag(QImageIOHandler::TransformationRotate90))
            sourceSize.transpose();
        if (!sourceSize.isValid() || sourceSize.isEmpty()) {
            m_error = u"Could not determine source size for: "_s + path;
            qCWarning(lcCProv).noquote() << m_error;
            return;
        }

        const qint64 missing = needsW
            ? qRound64(static_cast<qreal>(size.height()) * sourceSize.width() / sourceSize.height())
            : qRound64(static_cast<qreal>(size.width()) * sourceSize.height() / sourceSize.width());
        if (missing > std::numeric_limits<int>::max()) {
            m_error = u"Requested image size is too large"_s;
            return;
        }
        const int dimension = std::max(1, static_cast<int>(missing));
        if (needsW)
            size.setWidth(dimension);
        else
            size.setHeight(dimension);
    }

    // Decode once in this worker and always return the requested dimensions,
    // including the first load, so small cards never upload a full wallpaper.
    m_image = ImageCacher::load(path, size, m_fillMode);
    if (m_image.isNull()) {
        m_error = u"Failed to decode source: "_s + path;
        qCWarning(lcCProv).noquote() << m_error;
    }
}

} // namespace

CachingImageProvider::CachingImageProvider(FillMode fillMode)
    : m_fillMode(fillMode) {}

QQuickImageResponse* CachingImageProvider::requestImageResponse(const QString& id, const QSize& requestedSize) {
    auto* const response = new CachingImageResponse(id, requestedSize, m_fillMode);
    QThreadPool::globalInstance()->start(response);
    return response;
}

} // namespace hyprstack::images
