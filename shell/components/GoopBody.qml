pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// One filled contour in the original goopUI density field. Elliptical corner
// arcs let the initial mass stay soft while its perimeter flows into a menu.
Shape {
    id: root
    required property real radiusX
    required property real radiusY
    property real lean: 0
    property string side: "bottom"
    property bool joinFrame: false
    readonly property real rx: Math.max(0,Math.min(width/2,radiusX))
    readonly property real ry: Math.max(0,Math.min(height/2,radiusY))
    readonly property real k: 0.5522847498307936
    readonly property bool flatTL: joinFrame && (side==="bottom" || side==="right")
    readonly property bool flatTR: joinFrame && (side==="bottom" || side==="left")
    readonly property bool flatBR: joinFrame && (side==="top" || side==="left")
    readonly property bool flatBL: joinFrame && (side==="top" || side==="right")
    readonly property real tlx: flatTL ? 0 : rx
    readonly property real tly: flatTL ? 0 : ry
    readonly property real trx: flatTR ? 0 : rx
    readonly property real try_: flatTR ? 0 : ry
    readonly property real brx: flatBR ? 0 : rx
    readonly property real bry: flatBR ? 0 : ry
    readonly property real blx: flatBL ? 0 : rx
    readonly property real bly: flatBL ? 0 : ry
    preferredRendererType: Shape.CurveRenderer

    function bend(x: real,y: real): real {
        const u=side==="bottom"?y/Math.max(.001,height):side==="top"?1-y/Math.max(.001,height):
            side==="right"?x/Math.max(.001,width):1-x/Math.max(.001,width);
        const v=Math.max(0,Math.min(1,u));
        return lean*v*v*(3-2*v);
    }
    function px(x: real,y: real): real {return x+((side==="bottom"||side==="top")?bend(x,y):0);}
    function py(x: real,y: real): real {return y+((side==="left"||side==="right")?bend(x,y):0);}

    ShapePath {
        strokeWidth: -1
        fillColor: "white"
        startX: root.px(root.tlx,0)
        startY: root.py(root.tlx,0)
        PathLine { x: root.px(root.width-root.trx,0); y: root.py(root.width-root.trx,0) }
        PathCubic {
            x: root.px(root.width,root.try_); y: root.py(root.width,root.try_)
            control1X: root.px(root.width-root.trx+root.k*root.trx,0); control1Y: root.py(root.width-root.trx+root.k*root.trx,0)
            control2X: root.px(root.width,root.try_-root.k*root.try_); control2Y: root.py(root.width,root.try_-root.k*root.try_)
        }
        PathLine { x: root.px(root.width,root.height-root.bry); y: root.py(root.width,root.height-root.bry) }
        PathCubic {
            x: root.px(root.width-root.brx,root.height); y: root.py(root.width-root.brx,root.height)
            control1X: root.px(root.width,root.height-root.bry+root.k*root.bry); control1Y: root.py(root.width,root.height-root.bry+root.k*root.bry)
            control2X: root.px(root.width-root.brx+root.k*root.brx,root.height); control2Y: root.py(root.width-root.brx+root.k*root.brx,root.height)
        }
        PathLine { x: root.px(root.blx,root.height); y: root.py(root.blx,root.height) }
        PathCubic {
            x: root.px(0,root.height-root.bly); y: root.py(0,root.height-root.bly)
            control1X: root.px(root.blx-root.k*root.blx,root.height); control1Y: root.py(root.blx-root.k*root.blx,root.height)
            control2X: root.px(0,root.height-root.bly+root.k*root.bly); control2Y: root.py(0,root.height-root.bly+root.k*root.bly)
        }
        PathLine { x: root.px(0,root.tly); y: root.py(0,root.tly) }
        PathCubic {
            x: root.px(root.tlx,0); y: root.py(root.tlx,0)
            control1X: root.px(0,root.tly-root.k*root.tly); control1Y: root.py(0,root.tly-root.k*root.tly)
            control2X: root.px(root.tlx-root.k*root.tlx,0); control2Y: root.py(root.tlx-root.k*root.tlx,0)
        }
    }
}
