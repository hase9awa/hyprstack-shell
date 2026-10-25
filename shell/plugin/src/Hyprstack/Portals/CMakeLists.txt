qml_module(hyprstack-portals
    URI Hyprstack.Portals
    SOURCES
        portal.hpp
        portalhost.cpp
        portalrequest.cpp
        settingsportal.cpp
        filechooserportal.cpp
        accessportal.cpp
        appchooserportal.cpp
        wallpaperportal.cpp
    LIBRARIES
        Qt::DBus
        Qt::Gui
)
