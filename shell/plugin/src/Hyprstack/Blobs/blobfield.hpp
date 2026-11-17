#pragma once

#include <qpointer.h>
#include <qvariant.h>

#include "blobshape.hpp"

namespace hyprstack::blobs {

// A complete liquid rim is submitted atomically and drawn once. Drawing each
// glob as a separate translucent item accumulates alpha at their intersections.
class BlobField : public BlobShape {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList shapes READ shapes WRITE setShapes NOTIFY shapesChanged)
    Q_PROPERTY(QQuickItem* source READ source WRITE setSource NOTIFY sourceChanged)

public:
    explicit BlobField(QQuickItem* parent = nullptr);
    ~BlobField() override;
    QVariantList shapes() const { return m_shapes; }
    void setShapes(const QVariantList& shapes);
    QQuickItem* source() const { return m_source; }
    void setSource(QQuickItem* source);
    Q_INVOKABLE void sync();

signals:
    void shapesChanged();
    void sourceChanged();

protected:
    void updatePolish() override;
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;

private:
    QVariantList m_shapes;
    QPointer<QQuickItem> m_source;
};

} // namespace hyprstack::blobs
