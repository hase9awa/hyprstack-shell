qml_module(hyprstack-blobs
    URI Hyprstack.Blobs
    SOURCES
        blobgroup.cpp
        blobshape.cpp
        blobrect.cpp
        blobinvertedrect.cpp
        blobmaterial.cpp
        blobfield.cpp
    LIBRARIES
        Qt::Quick
)

qt_add_shaders(hyprstack-blobs "blob_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    FILES
        shaders/blob.frag
        shaders/blob.vert
        shaders/goop-blur.frag
        shaders/goop-edge.frag
        shaders/goop-frame.frag
        shaders/goop-content.frag
        shaders/goop.vert
)
