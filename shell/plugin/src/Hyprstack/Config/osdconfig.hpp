#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"
#include "enums.hpp"

namespace hyprstack::config {

class OsdConfig : public settings::ObjectNode {
    CONFIG_NODE(OsdConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_ENUM_PROPERTY(OsdSide, side, OsdSide::Right)
    CONFIG_PROPERTY(bool, showOnHover, true)
    CONFIG_PROPERTY(int, hideDelay, 2000)
    CONFIG_PROPERTY(bool, enableBrightness, true)
    CONFIG_PROPERTY(bool, enableMicrophone, false)
};

} // namespace hyprstack::config
