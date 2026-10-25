qml_module(hyprstack-portals
    URI Hyprstack.Portals
    SOURCES
        portal.hpp
        portalhost.cpp
        settingsportal.cpp
        filechooserportal.cpp
    LIBRARIES
        Qt::DBus
        Qt::Gui
)
