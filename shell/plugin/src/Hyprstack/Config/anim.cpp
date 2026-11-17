#include "anim.hpp"

#include <qpoint.h>
#include <cmath>
#include <numbers>

#include "appearanceconfig.hpp"
#include "tokens.hpp"
#include "motionpresets.hpp"

namespace hyprstack::config {

AnimTokens::AnimTokens(QObject* parent)
    : QObject(parent) {}

QEasingCurve AnimTokens::emphasized() const {
    return m_emphasized;
}

QEasingCurve AnimTokens::emphasizedAccel() const {
    return m_emphasizedAccel;
}

QEasingCurve AnimTokens::emphasizedDecel() const {
    return m_emphasizedDecel;
}

QEasingCurve AnimTokens::standard() const {
    return m_standard;
}

QEasingCurve AnimTokens::standardAccel() const {
    return m_standardAccel;
}

QEasingCurve AnimTokens::standardDecel() const {
    return m_standardDecel;
}

QEasingCurve AnimTokens::expressiveFastSpatial() const {
    return m_expressiveFastSpatial;
}

QEasingCurve AnimTokens::expressiveDefaultSpatial() const {
    return m_expressiveDefaultSpatial;
}

QEasingCurve AnimTokens::expressiveSlowSpatial() const {
    return m_expressiveSlowSpatial;
}

QEasingCurve AnimTokens::expressiveFastEffects() const {
    return m_expressiveFastEffects;
}

QEasingCurve AnimTokens::expressiveDefaultEffects() const {
    return m_expressiveDefaultEffects;
}

QEasingCurve AnimTokens::expressiveSlowEffects() const {
    return m_expressiveSlowEffects;
}

AnimDurations* AnimTokens::durations() const {
    return m_durations;
}

QEasingCurve AnimTokens::buildCurve(const QList<qreal>& points) {
    QEasingCurve curve(QEasingCurve::BezierSpline);

    // Points come in pairs of (x, y) forming cubic bezier segments.
    // Each segment needs 3 control points: c1, c2, endPoint.
    // So 6 values per segment: c1x, c1y, c2x, c2y, endX, endY.
    for (int i = 0; i + 5 < points.size(); i += 6) {
        const QPointF c1(points[i], points[i + 1]);
        const QPointF c2(points[i + 2], points[i + 3]);
        const QPointF end(points[i + 4], points[i + 5]);
        curve.addCubicBezierSegment(c1, c2, end);
    }

    return curve;
}

void AnimTokens::rebuildCurves() {
    if (!m_curves)
        return;

    m_emphasized = buildCurve(m_curves->emphasized());
    m_emphasizedAccel = buildCurve(m_curves->emphasizedAccel());
    m_emphasizedDecel = buildCurve(m_curves->emphasizedDecel());
    m_standard = buildCurve(m_curves->standard());
    m_standardAccel = buildCurve(m_curves->standardAccel());
    m_standardDecel = buildCurve(m_curves->standardDecel());
    m_expressiveFastSpatial = buildCurve(m_curves->expressiveFastSpatial());
    m_expressiveDefaultSpatial = buildCurve(m_curves->expressiveDefaultSpatial());
    m_expressiveSlowSpatial = buildCurve(m_curves->expressiveSlowSpatial());
    m_expressiveFastEffects = buildCurve(m_curves->expressiveFastEffects());
    m_expressiveDefaultEffects = buildCurve(m_curves->expressiveDefaultEffects());
    m_expressiveSlowEffects = buildCurve(m_curves->expressiveSlowEffects());

    const auto preset = m_profile ? motion::presetIndex(m_profile->shellPreset()) : 0;
    if (preset != 0) {
        // Effects stay monotonic: spring overshoot belongs to geometry, never opacity/colour.
        const auto effects = buildCurve({0.2, 0, 0.2, 1, 1, 1});
        auto spatial = effects;
        if (preset == 1) {
            spatial = springCurve(0.4, 0.72, 0.56);
        } else if (preset == 2) {
            spatial = buildCurve({0.16, 1, 0.3, 1, 1, 1});
        } else if (preset == 3) {
            spatial = buildCurve({0.22, 1, 0.36, 1, 1, 1});
        } else if (preset == 4) {
            spatial = buildCurve({0.76, 0, 0.24, 1, 1, 1});
        }
        m_standard = spatial;
        m_standardAccel = buildCurve({0.4, 0, 1, 1, 1, 1});
        m_standardDecel = spatial;
        m_emphasized = spatial;
        m_emphasizedAccel = m_standardAccel;
        m_emphasizedDecel = spatial;
        m_expressiveFastSpatial = preset == 1 ? springCurve(0.28, 0.6, 0.34) : spatial;
        m_expressiveDefaultSpatial = spatial;
        m_expressiveSlowSpatial = preset == 1 ? springCurve(0.5, 0.78, 0.68) : spatial;
        m_expressiveFastEffects = effects;
        m_expressiveDefaultEffects = effects;
        m_expressiveSlowEffects = effects;
    }

    emit curvesChanged();
}

QEasingCurve AnimTokens::springCurve(qreal response, qreal damping, qreal duration) {
    // Sample an analytic damped spring as cubic Hermite segments. Goop's tab
    // head/tail response and damping ratios inform the feel; no per-frame timer.
    const auto w = 2 * std::numbers::pi_v<qreal> / response;
    const auto wd = w * std::sqrt(1 - damping * damping);
    const auto value = [=](qreal t) {
        const auto seconds = t * duration;
        return 1 - std::exp(-damping * w * seconds)
            * (std::cos(wd * seconds) + damping * w / wd * std::sin(wd * seconds));
    };
    const auto slope = [=](qreal t) {
        return duration * w * w / wd * std::exp(-damping * w * t * duration)
            * std::sin(wd * t * duration);
    };
    QEasingCurve curve(QEasingCurve::BezierSpline);
    // Qt's BezierEase allocates ten segment slots internally (also in Qt 6.12).
    // Eight Hermite segments retain the spring's shape without overflowing it.
    constexpr int segments = 8;
    constexpr qreal step = 1.0 / segments;
    for (int i = 0; i < segments; ++i) {
        const auto a = i * step;
        const auto b = (i + 1) * step;
        const auto end = i == segments - 1 ? 1.0 : value(b);
        const auto endSlope = i == segments - 1 ? 0.0 : slope(b);
        curve.addCubicBezierSegment({a + step / 3, value(a) + slope(a) * step / 3},
            {b - step / 3, end - endSlope * step / 3}, {b, end});
    }
    return curve;
}

void AnimTokens::bindProfile(AppearanceAnim* profile) {
    if (m_profile == profile) return;
    if (m_profile) disconnect(m_profile, nullptr, this, nullptr);
    m_profile = profile;
    connect(profile, &AppearanceAnim::shellPresetChanged, this, &AnimTokens::rebuildCurves);
    rebuildCurves();
}

void AnimTokens::bindCurves(AnimCurves* curves) {
    m_curves = curves;

    // Rebuild when any curve control points change
    connect(curves, &AnimCurves::optionChanged, this, &AnimTokens::rebuildCurves);

    rebuildCurves();
}

void AnimTokens::bindDurations(AnimDurations* durations) {
    if (m_durations == durations)
        return;

    m_durations = durations;
    emit durationsChanged();
}

} // namespace hyprstack::config
