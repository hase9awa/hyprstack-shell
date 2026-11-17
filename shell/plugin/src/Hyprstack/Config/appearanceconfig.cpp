#include "appearanceconfig.hpp"
#include "motionpresets.hpp"

#include "tokens.hpp"

namespace hyprstack::config {

namespace {

// Helper: connect all changed signals from a token object to a single valuesChanged signal,
// plus connect the local scaleChanged signal.
template <typename Source, typename Target> void connectTokenSignals(Source* source, Target* target) {
    const auto* meta = source->metaObject();

    for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
        const auto prop = meta->property(i);

        if (prop.hasNotifySignal())
            QObject::connect(source, prop.notifySignal(), target,
                target->metaObject()->method(target->metaObject()->indexOfSignal("valuesChanged()")));
    }

    QObject::connect(target, &Target::scaleChanged, target, &Target::valuesChanged);
}

} // namespace

// AppearanceRounding

void AppearanceRounding::bindTokens(RoundingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearanceRounding::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * scale() * m_uiScale) : 0;
}

int AppearanceRounding::full() const {
    return m_tokens ? m_tokens->full() : 0;
}

// AppearanceSpacing

void AppearanceSpacing::bindTokens(SpacingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearanceSpacing::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * scale() * m_uiScale) : 0;
}

int AppearanceSpacing::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * scale() * m_uiScale) : 0;
}

// AppearancePadding

void AppearancePadding::bindTokens(PaddingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearancePadding::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * scale() * m_uiScale) : 0;
}

int AppearancePadding::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * scale() * m_uiScale) : 0;
}

int AppearancePadding::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * scale() * m_uiScale) : 0;
}

int AppearancePadding::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * scale() * m_uiScale) : 0;
}

int AppearancePadding::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * scale() * m_uiScale) : 0;
}

int AppearancePadding::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * scale() * m_uiScale) : 0;
}

int AppearancePadding::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * scale() * m_uiScale) : 0;
}

int AppearancePadding::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * scale() * m_uiScale) : 0;
}

// AnimDurations

void AnimDurations::setPreset(const QString& preset) {
    const auto index = motion::presetIndex(preset);
    if (m_preset == index) return;
    m_preset = index;
    emit valuesChanged();
}

int AnimDurations::duration(int token, int role) const {
    const auto value = m_preset == 0 ? token
        : motion::durations.at(static_cast<std::size_t>(m_preset - 1)).at(static_cast<std::size_t>(role));
    const auto factor = std::isfinite(m_scale) ? std::clamp(m_scale, 0.0, 10.0) : 1.0;
    return static_cast<int>(value * factor);
}

void AnimDurations::bindTokens(AnimDurationTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AnimDurations::small() const {
    return m_tokens ? duration(m_tokens->small(), 0) : 0;
}

int AnimDurations::normal() const {
    return m_tokens ? duration(m_tokens->normal(), 1) : 0;
}

int AnimDurations::large() const {
    return m_tokens ? duration(m_tokens->large(), 2) : 0;
}

int AnimDurations::extraLarge() const {
    return m_tokens ? duration(m_tokens->extraLarge(), 3) : 0;
}

int AnimDurations::expressiveFastSpatial() const {
    return m_tokens ? duration(m_tokens->expressiveFastSpatial(), 4) : 0;
}

int AnimDurations::expressiveDefaultSpatial() const {
    return m_tokens ? duration(m_tokens->expressiveDefaultSpatial(), 5) : 0;
}

int AnimDurations::expressiveSlowSpatial() const {
    return m_tokens ? duration(m_tokens->expressiveSlowSpatial(), 6) : 0;
}

int AnimDurations::expressiveFastEffects() const {
    return m_tokens ? duration(m_tokens->expressiveFastEffects(), 7) : 0;
}

int AnimDurations::expressiveDefaultEffects() const {
    return m_tokens ? duration(m_tokens->expressiveDefaultEffects(), 8) : 0;
}

int AnimDurations::expressiveSlowEffects() const {
    return m_tokens ? duration(m_tokens->expressiveSlowEffects(), 9) : 0;
}

} // namespace hyprstack::config
