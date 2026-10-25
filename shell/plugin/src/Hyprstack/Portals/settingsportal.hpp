#pragma once

#include <qcolor.h>
#include <qdbusabstractadaptor.h>
#include <qdbusargument.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qmap.h>
#include <qmetatype.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include "portal.hpp"

namespace hyprstack::portals {

// org.freedesktop.appearance reports the accent as three doubles.
struct AccentColour {
    double red = 0;
    double green = 0;
    double blue = 0;
};

QDBusArgument& operator<<(QDBusArgument& argument, const AccentColour& colour);
const QDBusArgument& operator>>(const QDBusArgument& argument, AccentColour& colour);

using SettingsMap = QMap<QString, QVariantMap>;

// org.freedesktop.impl.portal.Settings. Applications that cannot see the
// shell's own configuration read their light or dark mode and accent here.
class SettingsPortal : public Portal {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(ColourScheme colourScheme READ colourScheme WRITE setColourScheme NOTIFY colourSchemeChanged)
    Q_PROPERTY(QColor accentColour READ accentColour WRITE setAccentColour NOTIFY accentColourChanged)
    Q_PROPERTY(Contrast contrast READ contrast WRITE setContrast NOTIFY contrastChanged)

public:
    enum class ColourScheme : quint8 {
        NoPreference = 0,
        Dark = 1,
        Light = 2,
    };
    Q_ENUM(ColourScheme)

    enum class Contrast : quint8 {
        Normal = 0,
        High = 1,
    };
    Q_ENUM(Contrast)

    explicit SettingsPortal(QObject* parent = nullptr);

    void exportOn(QObject* target) override;
    [[nodiscard]] QString interfaceName() const override;

    [[nodiscard]] ColourScheme colourScheme() const;
    void setColourScheme(ColourScheme scheme);
    [[nodiscard]] QColor accentColour() const;
    void setAccentColour(const QColor& colour);
    [[nodiscard]] Contrast contrast() const;
    void setContrast(Contrast contrast);

    [[nodiscard]] SettingsMap readAll(const QStringList& patterns) const;
    // An invalid variant means the key is not served here.
    [[nodiscard]] QVariant read(const QString& group, const QString& key) const;

signals:
    void colourSchemeChanged();
    void accentColourChanged();
    void contrastChanged();
    void settingChanged(const QString& group, const QString& key, const QDBusVariant& value);

private:
    [[nodiscard]] QVariantMap appearance() const;
    void announce(const QString& key);

    ColourScheme m_colourScheme = ColourScheme::NoPreference;
    QColor m_accentColour;
    Contrast m_contrast = Contrast::Normal;
};

// Qt leaves QDBusContext unset inside adaptor slots, so a key this backend
// does not serve is refused by replying to the call by hand. The published
// interface is spelled out because the manual reply hides the return value
// from the description moc would otherwise generate.
class SettingsAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Settings")
    Q_CLASSINFO("D-Bus Introspection",
        "  <interface name=\"org.freedesktop.impl.portal.Settings\">\n"
        "    <property name=\"version\" type=\"u\" access=\"read\"/>\n"
        "    <method name=\"ReadAll\">\n"
        "      <arg name=\"namespaces\" type=\"as\" direction=\"in\"/>\n"
        "      <arg name=\"value\" type=\"a{sa{sv}}\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"Read\">\n"
        "      <arg name=\"namespace\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"key\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <method name=\"ReadOne\">\n"
        "      <arg name=\"namespace\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"key\" type=\"s\" direction=\"in\"/>\n"
        "      <arg name=\"value\" type=\"v\" direction=\"out\"/>\n"
        "    </method>\n"
        "    <signal name=\"SettingChanged\">\n"
        "      <arg name=\"namespace\" type=\"s\"/>\n"
        "      <arg name=\"key\" type=\"s\"/>\n"
        "      <arg name=\"value\" type=\"v\"/>\n"
        "    </signal>\n"
        "  </interface>\n")

    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit SettingsAdaptor(SettingsPortal* portal, QObject* parent);

    [[nodiscard]] static uint version();

    // NOLINTBEGIN(readability-identifier-naming) D-Bus spells its methods this way
public slots:
    hyprstack::portals::SettingsMap ReadAll(const QStringList& patterns);
    void Read(const QString& group, const QString& key, const QDBusMessage& message);
    void ReadOne(const QString& group, const QString& key, const QDBusMessage& message);

signals:
    void SettingChanged(const QString& group, const QString& key, const QDBusVariant& value);
    // NOLINTEND(readability-identifier-naming)

private:
    void reply(const QString& group, const QString& key, const QDBusMessage& message);

    SettingsPortal* m_portal;
};

} // namespace hyprstack::portals

Q_DECLARE_METATYPE(hyprstack::portals::AccentColour)
