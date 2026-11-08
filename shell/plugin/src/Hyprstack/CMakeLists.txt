qml_module(hyprstack-core
    URI Hyprstack
    INCLUDE_PREFIX core
    SOURCES
        animationclock.cpp
        cutils.cpp
        qalculator.cpp
        requests.cpp
        toaster.cpp
        circularbuffer.cpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt6::QuickPrivate
        Qt::Concurrent
        PkgConfig::Qalculate
        hyprstack-util
)

# Bake the shell version in so CUtils can expose it without spawning a process
target_compile_definitions(hyprstack-core PRIVATE HYPRSTACK_VERSION="${VERSION}")

# Node macros expand to Q_OBJECT, automoc can't see it otherwise
list(APPEND CMAKE_AUTOMOC_MACRO_NAMES
    SETTINGS_NODE SETTINGS_NODE_NO_CTOR SETTINGS_LIST_TYPE
    CONFIG_NODE CONFIG_NODE_NO_CTOR CONFIG_LIST_TYPE
)

add_subdirectory(Settings)
add_subdirectory(Components)
add_subdirectory(Config)
add_subdirectory(Models)
add_subdirectory(Portals)
add_subdirectory(Services)
add_subdirectory(Blobs)
add_subdirectory(Images)
add_subdirectory(I18n)
