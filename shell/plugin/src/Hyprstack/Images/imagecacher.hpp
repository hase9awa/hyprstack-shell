#pragma once

#include <qimage.h>
#include <qsize.h>
#include <qstring.h>

namespace hyprstack::images {

class ImageCacher {
public:
    enum class FillMode : quint8 {
        Crop,
        Fit,
        Stretch,
    };

    static QImage load(const QString& sourcePath, const QSize& size, FillMode fillMode);

private:
    static const QString& cacheDir();
    static QString cachePathFor(const QString& sourcePath, const QSize& size, FillMode fillMode);
};

} // namespace hyprstack::images
