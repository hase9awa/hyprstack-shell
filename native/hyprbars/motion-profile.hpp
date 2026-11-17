// Shared motion for the scrolling camera and taskbar transforms. Application
// geometry remains owned by Hyprland; only their visual interpolation changes.
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <string_view>

namespace HyprstackMotion {
enum class Preset { Default, Spring, Glide, Snappy, Cinematic, Reduced };
inline Preset preset = Preset::Default;
inline bool gameMode = false;

inline Preset fromName(std::string_view name) {
    if (name == "spring") return Preset::Spring;
    if (name == "glide") return Preset::Glide;
    if (name == "snappy") return Preset::Snappy;
    if (name == "cinematic") return Preset::Cinematic;
    if (name == "reduced") return Preset::Reduced;
    return Preset::Default;
}

inline double duration(double original, bool camera = false) {
    if (gameMode || preset == Preset::Reduced) return 0;
    switch (preset) {
        case Preset::Spring: return camera ? .48 : .34;
        case Preset::Glide: return camera ? .42 : .26;
        case Preset::Snappy: return camera ? .25 : .14;
        case Preset::Cinematic: return camera ? .65 : .40;
        default: return original;
    }
}

inline double eased(double t, Preset profile) {
    t = std::clamp(t, 0.0, 1.0);
    if (t == 0 || t == 1) return t;
    std::array<double, 4> c{.22, 1.25, .32, 1};
    if (profile == Preset::Glide) c = {.16, 1, .3, 1};
    else if (profile == Preset::Snappy) c = {.22, 1, .36, 1};
    else if (profile == Preset::Cinematic) c = {.76, 0, .24, 1};
    const auto cubic = [](double u, double a, double b) {
        return 3 * (1-u) * (1-u) * u * a + 3 * (1-u) * u * u * b + u * u * u;
    };
    double low = 0, high = 1;
    for (int i = 0; i < 24; ++i) {
        const auto mid = (low + high) / 2;
        if (cubic(mid, c[0], c[2]) < t) low = mid;
        else high = mid;
    }
    return cubic((low + high) / 2, c[1], c[3]);
}
} // namespace HyprstackMotion
