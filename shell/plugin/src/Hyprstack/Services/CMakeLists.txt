if(HYPRSTACK_AUDIO_VISUALIZER)
    set(audio_sources beattracker.cpp audiocollector.cpp audioprovider.cpp cavaprovider.cpp)
    set(audio_libraries PkgConfig::Pipewire PkgConfig::Aubio PkgConfig::Cava)
else()
    set(audio_sources audiostubs.cpp)
endif()

qml_module(hyprstack-services
    URI Hyprstack.Services
    SOURCES
        service.cpp
        serviceref.cpp
        ${audio_sources}
        tickingservice.cpp
        sensorslib.cpp
        cpu.cpp
        gpu.cpp
        memory.cpp
        diskinfo.cpp
        storage.cpp
        filevolumes.cpp
        lyriccandidate.cpp
        lyrics.cpp
        sessionmanager.cpp
        bluezagent.cpp
        nmsecretagent.cpp
        networkusage.cpp
        hyprdevices.cpp
        hyprextras.cpp
    LIBRARIES
        Qt::Concurrent
        Qt::DBus
        Qt::Network
        ${audio_libraries}
        Sensors::Sensors
        hyprstack-util
        hyprstack-core
        hyprstack-config
    DEPENDENCIES
        Hyprstack
        Hyprstack.Config
)
