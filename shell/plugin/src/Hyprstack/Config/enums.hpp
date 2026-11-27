#pragma once

#include <qobject.h>
#include <qqmlintegration.h>

namespace hyprstack::config {

#define ENUM(Name, ...)                                                                                                \
    namespace Name {                                                                                                   \
                                                                                                                       \
    Q_NAMESPACE                                                                                                        \
    QML_ELEMENT                                                                                                        \
                                                                                                                       \
    enum Enum : quint8 {                                                                                               \
        __VA_ARGS__                                                                                                    \
    };                                                                                                                 \
    Q_ENUM_NS(Enum)                                                                                                    \
                                                                                                                       \
    };

ENUM(BarWorkspaceDisplay, Shapes, Text, Icons)
ENUM(BarWorkspaceCapitalisation, Preserve, Upper, Lower)
ENUM(LyricsBackend, Auto, Local, LRCLIB, NetEase)
ENUM(GpuType, Auto, Nvidia, Generic, None)
ENUM(NotifsFullscreen, On, Off)
ENUM(TemperatureUnit, Auto, Celsius, Fahrenheit, Kelvin)
ENUM(DataUnit, Binary, Decimal)
ENUM(ClockFormat, Auto, TwelveHour, TwentyFourHour)
ENUM(OsdSide, Left, Right)
// Pointer settings the shell has not been told to manage keep whatever the
// compositor already uses, so hypr-vars.lua stays in charge until then.
ENUM(PointerTriState, Inherit, On, Off)

#undef ENUM

} // namespace hyprstack::config
