#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"
#include "enums.hpp"

namespace hyprstack::config {

using Qt::StringLiterals::operator""_s;

// Mouse, touchpad and cursor settings the shell passes to Hyprland. Every
// default is a sentinel for "inherit": an untouched setting is never written
// to shell.json and never applied, so hypr-vars.lua and the Hyprland config
// keep owning it until the user moves the matching control.
class PointerConfig : public settings::ObjectNode {
    CONFIG_NODE(PointerConfig, settings::ObjectNode)

    // Mouse
    CONFIG_PROPERTY(double, sensitivity, -2.0)  // Inherit, otherwise -1.0 to 1.0
    CONFIG_PROPERTY(QString, accelProfile, {})  // Inherit, otherwise "adaptive" or "flat"
    CONFIG_ENUM_PROPERTY(PointerTriState, naturalScroll, PointerTriState::Inherit)
    CONFIG_PROPERTY(double, scrollFactor, -1.0) // Inherit, otherwise 0.0 to 100.0
    CONFIG_ENUM_PROPERTY(PointerTriState, leftHanded, PointerTriState::Inherit)
    CONFIG_PROPERTY(int, followMouse, -1)       // Inherit, otherwise 0 to 3

    // Touchpad
    CONFIG_ENUM_PROPERTY(PointerTriState, touchpadNaturalScroll, PointerTriState::Inherit)
    CONFIG_ENUM_PROPERTY(PointerTriState, touchpadTapToClick, PointerTriState::Inherit)
    CONFIG_ENUM_PROPERTY(PointerTriState, touchpadDisableWhileTyping, PointerTriState::Inherit)
    CONFIG_PROPERTY(double, touchpadScrollFactor, -1.0)

    // Cursor
    CONFIG_PROPERTY(QString, cursorTheme, {})      // Inherit, otherwise a theme name
    CONFIG_PROPERTY(int, cursorSize, 0)            // Inherit, otherwise 8 to 64
    CONFIG_PROPERTY(double, cursorHideTimeout, -1.0) // Inherit, otherwise seconds (0 = never)
};

} // namespace hyprstack::config
