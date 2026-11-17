#include "blobfield.hpp"

#include <qsgnode.h>

#include <algorithm>
#include <cmath>

#include "blobgroup.hpp"

namespace hyprstack::blobs {

using namespace Qt::StringLiterals;

BlobField::BlobField(QQuickItem* parent) : BlobShape(parent) {}

BlobField::~BlobField() {
    unregisterFromGroup();
}

void BlobField::setShapes(const QVariantList& shapes) {
    if (m_shapes == shapes) return;
    m_shapes = shapes;
    emit shapesChanged();
    sync();
}

void BlobField::setSource(QQuickItem* source) {
    if (m_source == source) return;
    m_source = source;
    emit sourceChanged();
    sync();
}

void BlobField::sync() {
    polish();
    update();
}

void BlobField::updatePolish() {
    m_cachedRects.clear();
    m_cachedMyIndex = -3; // One draw for the entire union, no per-glob ownership.
    m_cachedCutoutIndex = 0;
    m_cachedHasInverted = false;
    m_localPaddedRect = {};
    if (!m_group || !m_source || m_shapes.isEmpty()) return;

    // Mapping happens during polish, after all QML animations and layouts have
    // advanced. A JS FrameAnimation sampling this earlier lags the panel a frame.
    const QPointF offset = m_source->mapToItem(this, QPointF());
    const QPointF axisX = m_source->mapToItem(this, QPointF(1, 0)) - offset;
    const QPointF axisY = m_source->mapToItem(this, QPointF(0, 1)) - offset;
    QRectF bounds;
    const int count = std::min(static_cast<int>(m_shapes.size()), k_maxRects);
    for (int i = 0; i < count; ++i) {
        const QVariantMap shape = m_shapes[i].toMap();
        const double x = shape.value(u"x"_s).toDouble();
        const double y = shape.value(u"y"_s).toDouble();
        const double w = shape.value(u"width"_s).toDouble();
        const double h = shape.value(u"height"_s).toDouble();
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(w) || !std::isfinite(h) || w <= 0 || h <= 0) {
            if (i == 0) return; // The first shape is always the real panel's cutout.
            continue;
        }
        BlobRectData rect;
        const bool absolute = shape.value(u"absolute"_s).toBool();
        const QPointF u = absolute ? QPointF(1, 0) : axisX;
        const QPointF v = absolute ? QPointF(0, 1) : axisY;
        const double angle = shape.value(u"rotation"_s).toDouble() * (std::acos(-1.0) / 180.0);
        const double co = std::cos(angle), si = std::sin(angle);
        const double xx = u.x() * co + v.x() * si, yx = u.y() * co + v.y() * si;
        const double xy = v.x() * co - u.x() * si, yy = v.y() * co - u.y() * si;
        const double det = xx * yy - yx * xy;
        if (!std::isfinite(det) || std::abs(det) < 1e-8) {
            if (i == 0) return;
            continue;
        }
        const QPointF center = (absolute ? QPointF() : offset) + u * (x + w / 2) + v * (y + h / 2);
        rect.cx = static_cast<float>(center.x());
        rect.cy = static_cast<float>(center.y());
        rect.hw = static_cast<float>(w / 2);
        rect.hh = static_cast<float>(h / 2);
        rect.screenHalfX = static_cast<float>(std::abs(xx) * w / 2 + std::abs(xy) * h / 2);
        rect.screenHalfY = static_cast<float>(std::abs(yx) * w / 2 + std::abs(yy) * h / 2);
        rect.invDeform[0] = static_cast<float>(yy / det);
        rect.invDeform[1] = static_cast<float>(-yx / det);
        rect.invDeform[2] = static_cast<float>(-xy / det);
        rect.invDeform[3] = static_cast<float>(xx / det);
        const double trace = xx * xx + yx * yx + xy * xy + yy * yy;
        rect.minEig = static_cast<float>(std::sqrt(std::max(0.0, (trace - std::sqrt(std::max(0.0, trace * trace - 4 * det * det))) / 2)));
        const int kind = std::clamp(shape.value(u"kind"_s).toInt(), 0, 2);
        rect.kind = static_cast<float>(kind);
        const double radius = shape.value(u"radius"_s, std::min(w, h) / 2).toDouble();
        const auto corner = [&](const QString& key) {
            const double value = shape.value(key, radius).toDouble();
            return static_cast<float>(std::isfinite(value) ? std::clamp(value, 0.0, std::min(w, h) / 2) : 0);
        };
        rect.radius[0] = corner(u"topRightRadius"_s);
        rect.radius[1] = corner(u"bottomRightRadius"_s);
        rect.radius[2] = corner(u"bottomLeftRadius"_s);
        rect.radius[3] = corner(u"topLeftRadius"_s);
        if (kind == 2) {
            rect.radius[0] = static_cast<float>(std::clamp(shape.value(u"radiusA"_s).toDouble(), 0.0, w / 2));
            rect.radius[1] = static_cast<float>(std::clamp(shape.value(u"radiusB"_s).toDouble(), 0.0, w / 2));
            rect.radius[2] = static_cast<float>(std::clamp(shape.value(u"span"_s).toDouble(), 0.0, h));
            rect.radius[3] = 0;
        }
        m_cachedRects.append(rect);
        // The panel itself is never repainted. Only allocate pixels around
        // the live rim and droplets, rather than shading the full window.
        if (i > 0) bounds = bounds.united(QRectF(rect.cx - rect.screenHalfX, rect.cy - rect.screenHalfY,
            rect.screenHalfX * 2, rect.screenHalfY * 2));
    }
    if (bounds.isEmpty()) return;
    const qreal pad = m_group->smoothing() + 2;
    m_localPaddedRect = bounds.adjusted(-pad, -pad, pad, pad);
    m_cachedPaddedX = static_cast<float>(m_localPaddedRect.x());
    m_cachedPaddedY = static_cast<float>(m_localPaddedRect.y());
    m_cachedPaddedW = static_cast<float>(m_localPaddedRect.width());
    m_cachedPaddedH = static_cast<float>(m_localPaddedRect.height());
}

QSGNode* BlobField::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) {
    if (m_localPaddedRect.isEmpty()) {
        delete oldNode;
        return nullptr;
    }
    return BlobShape::updatePaintNode(oldNode, data);
}

} // namespace hyprstack::blobs
