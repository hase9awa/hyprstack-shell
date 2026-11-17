#include "tokensattached.hpp"

#include <qquickitem.h>

#include "common.hpp"

namespace hyprstack::config {

namespace {

const AppearanceConfig* resolveAppearance(const ConfigRoot* config, bool complete, const char* prop, QObject* parent) {
    if (config)
        return config->appearance();
    if ((complete || !qobject_cast<QQuickItem*>(parent)) && parent)
        qCWarning(lcConfig, "Tokens.%s accessed without a screen set on %s", prop, parent->metaObject()->className());
    return ConfigSingleton::instance()->appearance();
}

} // namespace

Tokens::Tokens(QObject* parent)
    : QQuickAttachedPropertyPropagator(parent)
    , m_font(new FontTokens(this))
    , m_anim(new AnimTokens(this)) {
    bindAnim();
    bindFont();
    initialize();
}

void Tokens::classBegin() {}

void Tokens::componentComplete() {
    m_complete = true;
}

QString Tokens::screen() const {
    return m_screen;
}

void Tokens::inheritScreen(const QString& screen) {
    if (screen == m_screen)
        return;

    m_screen = screen;

    if (m_screen.isEmpty()) {
        m_config = nullptr;
        m_tokens = nullptr;
    } else {
        m_config = ConfigSingleton::instance()->forScreen(m_screen);
        m_tokens = TokensSingleton::instance()->forScreen(m_screen);
    }

    bindFont();
    propagateScreen();
    emit sourceChanged();
}

void Tokens::propagateScreen() {
    const auto children = attachedChildren();
    for (auto* const child : children) {
        auto* const tokens = qobject_cast<Tokens*>(child);
        if (tokens)
            tokens->inheritScreen(m_screen);
    }
}

void Tokens::attachedParentChange(
    QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) {
    Q_UNUSED(oldParent);
    const auto* tokens = qobject_cast<Tokens*>(newParent);
    if (tokens)
        inheritScreen(tokens->screen());
}

void Tokens::bindAnim() {
    m_anim->bindProfile(ConfigSingleton::instance()->appearance()->anim());
    m_anim->bindDurations(ConfigSingleton::instance()->appearance()->anim()->durations());
    m_anim->bindCurves(TokensSingleton::instance()->appearance()->curves());
}

void Tokens::bindFont() {
    auto* appearance = m_config ? m_config->appearance() : ConfigSingleton::instance()->appearance();
    m_font->bindFont(appearance->font());
    QObject::disconnect(m_scaleConnection);
    const auto updateScale = [this, appearance] {
        m_font->setUiScale(appearance->effectiveScale());
        emit scaleChanged();
    };
    m_scaleConnection = connect(appearance, &AppearanceConfig::scaleChanged, this, updateScale);
    updateScale();
    auto* tokens = m_tokens ? m_tokens : TokensSingleton::instance();
    tokens->scaledSizes()->bindScale(appearance);
}

#define TOKENS_ATTACHED_GETTER(Type, name)                                                                             \
    const Type* Tokens::name() const {                                                                                 \
        auto* a = resolveAppearance(m_config, m_complete, #name, parent());                                            \
        return a ? a->name() : nullptr;                                                                                \
    }

TOKENS_ATTACHED_GETTER(AppearanceRounding, rounding)
TOKENS_ATTACHED_GETTER(AppearanceSpacing, spacing)
TOKENS_ATTACHED_GETTER(AppearancePadding, padding)

#undef TOKENS_ATTACHED_GETTER

const AppearanceTransparency* Tokens::transparency() {
    return ConfigSingleton::instance()->appearance()->transparency(); // Transparency is always global
}

qreal Tokens::scale() const {
    const auto* appearance = m_config ? m_config->appearance() : ConfigSingleton::instance()->appearance();
    return appearance->effectiveScale();
}

const ScaledSizeTokens* Tokens::sizes() const {
    if (m_tokens)
        return m_tokens->scaledSizes();
    if ((m_complete || !qobject_cast<QQuickItem*>(parent())) && parent())
        qCWarning(lcConfig, "Tokens.sizes accessed without a screen set on %s", parent()->metaObject()->className());
    return TokensSingleton::instance()->scaledSizes();
}

const FontTokens* Tokens::font() const {
    return m_font;
}

const AnimTokens* Tokens::anim() const {
    return m_anim;
}

TokensRoot* Tokens::forScreen(const QString& screen) {
    return TokensSingleton::instance()->forScreen(screen);
}

Tokens* Tokens::qmlAttachedProperties(QObject* object) {
    return new Tokens(object);
}

} // namespace hyprstack::config
