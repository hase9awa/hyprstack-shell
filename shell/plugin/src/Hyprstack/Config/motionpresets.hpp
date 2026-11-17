#pragma once

#include <array>
#include <qstringview.h>

namespace hyprstack::config::motion {

// Keep the default profile token-backed, including user shell-tokens.json overrides.
inline int presetIndex(QStringView id) {
    if (id == u"goop") return 1;
    if (id == u"fluent") return 2;
    if (id == u"snappy") return 3;
    if (id == u"cinematic") return 4;
    if (id == u"reduced") return 5;
    return 0;
}

// small, normal, large, extraLarge, fast/default/slow spatial, fast/default/slow effects.
inline constexpr std::array<std::array<int, 10>, 5> durations {{
    {{160, 300, 460, 640, 280, 460, 560, 100, 150, 210}}, // Goop
    {{120, 240, 340, 460, 180, 300, 420, 100, 160, 220}}, // Fluent
    {{ 90, 160, 240, 340, 140, 210, 290,  70, 110, 160}}, // Snappy
    {{240, 440, 680, 900, 320, 520, 740, 160, 260, 380}}, // Cinematic
    {{  0,   0,   0,   0,   0,   0,   0,   0,   0,   0}}, // Reduced motion
}};

} // namespace hyprstack::config::motion
