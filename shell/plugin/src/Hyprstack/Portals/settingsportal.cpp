#include "settingsportal.hpp"

#include <qdbusconnection.h>
#include <qdbusmetatype.h>
#include <qloggingcategory.h>

namespace {

Q_LOGGING_CATEGORY(lcSettingsPortal, "hyprstack.portals.settings", QtInfoMsg)

} // namespace

namespace hyprstack::portals {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_interface = u"org.freedesktop.impl.portal.Settings"_s;
const QString k_appearance = u"org.freedesktop.appearance"_s;
const QString k_colourScheme = u"color-scheme"_s;
const QString k_accentColour = u"accent-color"_s;
const QString k_contrast = u"contrast"_s;
const QString k_notFound = u"org.freedesktop.portal.Error.NotFound"_s;

// Interface version. Below 2 the desktop portal falls back to Read.
constexpr uint k_version = 2;

// Namespaces arrive as the globs described by the portal specification: an
// empty list asks for everything, a trailing star matches a whole subtree.
bool matches(const QStringList& patterns, const QString& group) {
    if (patterns.isEmpty())
        return true;

    for (const auto& pattern : patterns) {
        if (pattern.isEmpty() || pattern == group)
            return true;
        if (pattern.endsWith(u'*') && group.startsWith(QStringView(pattern).chopped(1)))
            return true;
    }

    return false;
}

} // namespace

QDBusArgument& operator<<(QDBusArgument& argument, const AccentColour& colour) {
    argument.beginStructure();
    argument << colour.red << colour.green << colour.blue;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, AccentColour& colour) {
    argument.beginStructure();
    argument >> colour.red >> colour.green >> colour.blue;
    argument.endStructure();
    return argument;
}

SettingsPortal::SettingsPortal(QObject* parent) : Portal(parent) {
    qDBusRegisterMetaType<AccentColour>();
    qDBusRegisterMetaType<SettingsMap>();
}

void SettingsPortal::exportOn(QObject* target) {
    new SettingsAdaptor(this, target); // NOLINT(cppcoreguidelines-owning-memory) parented to target
}

QString SettingsPortal::interfaceName() const {
    return k_interface;
}

SettingsPortal::ColourScheme SettingsPortal::colourScheme() const {
    return m_colourScheme;
}

void SettingsPortal::setColourScheme(ColourScheme scheme) {
    if (m_colourScheme == scheme)
        return;
    m_colourScheme = scheme;
    emit colourSchemeChanged();
    announce(k_colourScheme);
}

QColor SettingsPortal::accentColour() const {
    return m_accentColour;
}

void SettingsPortal::setAccentColour(const QColor& colour) {
    if (m_accentColour == colour)
        return;
    m_accentColour = colour;
    emit accentColourChanged();
    announce(k_accentColour);
}

SettingsPortal::Contrast SettingsPortal::contrast() const {
    return m_contrast;
}

void SettingsPortal::setContrast(Contrast contrast) {
    if (m_contrast == contrast)
        return;
    m_contrast = contrast;
    emit contrastChanged();
    announce(k_contrast);
}

SettingsMap SettingsPortal::readAll(const QStringList& patterns) const {
    SettingsMap values;
    if (matches(patterns, k_appearance))
        values.insert(k_appearance, appearance());
    return values;
}

QVariant SettingsPortal::read(const QString& group, const QString& key) const {
    if (group != k_appearance)
        return {};

    const auto values = appearance();
    const auto value = values.constFind(key);
    return value == values.constEnd() ? QVariant() : *value;
}

QVariantMap SettingsPortal::appearance() const {
    // An unset accent is reported as the specification's "no colour" triple
    // rather than being left out, so applications stop looking for one.
    const auto accent = m_accentColour.isValid()
        ? AccentColour { static_cast<double>(m_accentColour.redF()), static_cast<double>(m_accentColour.greenF()),
              static_cast<double>(m_accentColour.blueF()) }
        : AccentColour { -1, -1, -1 };

    return {
        { k_colourScheme, QVariant::fromValue(static_cast<uint>(m_colourScheme)) },
        { k_accentColour, QVariant::fromValue(accent) },
        { k_contrast, QVariant::fromValue(static_cast<uint>(m_contrast)) },
    };
}

void SettingsPortal::announce(const QString& key) {
    const auto value = read(k_appearance, key);
    if (!value.isValid())
        return;
    emit settingChanged(k_appearance, key, QDBusVariant(value));
}

SettingsAdaptor::SettingsAdaptor(SettingsPortal* portal, QObject* parent)
    : QDBusAbstractAdaptor(parent), m_portal(portal) {
    connect(portal, &SettingsPortal::settingChanged, this, &SettingsAdaptor::SettingChanged);
}

uint SettingsAdaptor::version() {
    return k_version;
}

SettingsMap SettingsAdaptor::ReadAll(const QStringList& patterns) {
    return m_portal->readAll(patterns);
}

void SettingsAdaptor::Read(const QString& group, const QString& key, const QDBusMessage& message) {
    reply(group, key, message);
}

void SettingsAdaptor::ReadOne(const QString& group, const QString& key, const QDBusMessage& message) {
    reply(group, key, message);
}

void SettingsAdaptor::reply(const QString& group, const QString& key, const QDBusMessage& message) {
    message.setDelayedReply(true);
    auto bus = QDBusConnection::sessionBus();

    const auto value = m_portal->read(group, key);
    if (!value.isValid()) {
        // The desktop portal reads this error as "ask the next backend", so
        // keys served elsewhere must not come back as an empty value.
        qCDebug(lcSettingsPortal) << "No value for" << group << key;
        bus.send(message.createErrorReply(k_notFound, u"%1 %2 is not provided by Hyprstack"_s.arg(group, key)));
        return;
    }

    bus.send(message.createReply(QVariant::fromValue(QDBusVariant(value))));
}

} // namespace hyprstack::portals
