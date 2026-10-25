#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qmetaobject.h>

#include "appearanceconfig.hpp"
#include "tokens.hpp"

namespace hyprstack::config {

// Render dimensions without changing the persisted, unscaled token values.
// Views are shared per screen instead of being allocated by every QML item.
class ScaledTokenGroup : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledTokenGroup(QObject* source, QObject* parent) : QObject(parent) {
        const auto notify = staticMetaObject.method(staticMetaObject.indexOfSignal("valuesChanged()"));
        const auto meta = source->metaObject();
        for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
            const auto prop = meta->property(i);
            if (prop.hasNotifySignal()) QObject::connect(source, prop.notifySignal(), this, notify);
        }
    }
    void setScale(qreal scale) {
        if (qFuzzyCompare(m_scale, scale)) return;
        m_scale = scale;
        emit valuesChanged();
    }
signals:
    void valuesChanged();
protected:
    qreal m_scale = 1;
};

#define SCALED_DIMENSION(name) \
    Q_PROPERTY(qreal name READ name NOTIFY valuesChanged) \
public: \
    [[nodiscard]] qreal name() const { return m_source->name() * m_scale; }
#define UNSCALED_VALUE(name) \
    Q_PROPERTY(qreal name READ name NOTIFY valuesChanged) \
public: \
    [[nodiscard]] qreal name() const { return m_source->name(); }

class ScaledBarTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledBarTokens(BarTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(innerWidth)
    SCALED_DIMENSION(windowPreviewSize)
    SCALED_DIMENSION(trayMenuWidth)
    SCALED_DIMENSION(batteryWidth)
    SCALED_DIMENSION(networkWidth)
    SCALED_DIMENSION(audioWidth)
    SCALED_DIMENSION(kbLayoutWidth)
private:
    BarTokens* m_source;
};

class ScaledDashboardTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledDashboardTokens(DashboardTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(tabIndicatorHeight)
    SCALED_DIMENSION(tabIndicatorSpacing)
    SCALED_DIMENSION(userWidth)
    SCALED_DIMENSION(logoSize)
    SCALED_DIMENSION(uptimeSize)
    SCALED_DIMENSION(dateTimeWidth)
    SCALED_DIMENSION(mediaWidth)
    UNSCALED_VALUE(mediaProgressSweep)
    SCALED_DIMENSION(mediaProgressThickness)
    SCALED_DIMENSION(resourceProgressThickness)
    SCALED_DIMENSION(weatherWidth)
    SCALED_DIMENSION(mediaCoverArtSize)
    SCALED_DIMENSION(mediaTabWidth)
    SCALED_DIMENSION(mediaTabHeight)
    SCALED_DIMENSION(mediaSectionWidth)
    SCALED_DIMENSION(perfHeroCardWidth)
    SCALED_DIMENSION(perfUsageShapeSize)
    SCALED_DIMENSION(perfStorageTextWidth)
    SCALED_DIMENSION(perfNetworkCardWidth)
    SCALED_DIMENSION(perfNetworkCardHeight)
    SCALED_DIMENSION(perfBattWidth)
    SCALED_DIMENSION(perfBattWidthSingle)
    SCALED_DIMENSION(perfBattHeight)
    SCALED_DIMENSION(perfPlaceholderWidth)
private:
    DashboardTokens* m_source;
};

class ScaledLauncherTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledLauncherTokens(LauncherTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(itemWidth)
    SCALED_DIMENSION(itemHeight)
    SCALED_DIMENSION(clipHeight)
    SCALED_DIMENSION(wallpaperWidth)
    SCALED_DIMENSION(wallpaperHeight)
private:
    LauncherTokens* m_source;
};

class ScaledNotifsTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledNotifsTokens(NotifsTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(width)
    SCALED_DIMENSION(image)
    SCALED_DIMENSION(badge)
private:
    NotifsTokens* m_source;
};

class ScaledOsdTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledOsdTokens(OsdTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(sliderWidth)
    SCALED_DIMENSION(sliderHeight)
private:
    OsdTokens* m_source;
};

class ScaledSessionTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledSessionTokens(SessionTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(button)
private:
    SessionTokens* m_source;
};

class ScaledSidebarTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledSidebarTokens(SidebarTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(width)
private:
    SidebarTokens* m_source;
};

class ScaledUtilitiesTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledUtilitiesTokens(UtilitiesTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    SCALED_DIMENSION(width)
    SCALED_DIMENSION(toastWidth)
private:
    UtilitiesTokens* m_source;
};

class ScaledLockTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledLockTokens(LockTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    UNSCALED_VALUE(heightMult)
    UNSCALED_VALUE(ratio)
    SCALED_DIMENSION(centerWidth)
    SCALED_DIMENSION(showWeatherDetailsHeight)
    SCALED_DIMENSION(showForecastHeight)
    SCALED_DIMENSION(forecastItemWidth)
    SCALED_DIMENSION(largeLogoWidth)
    SCALED_DIMENSION(largeFontWidth)
    SCALED_DIMENSION(fetch4LinesHeight)
    SCALED_DIMENSION(fetch3LinesHeight)
    SCALED_DIMENSION(showColourBoxRowHeight)
private:
    LockTokens* m_source;
};

class ScaledWInfoTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledWInfoTokens(WInfoTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    UNSCALED_VALUE(heightMult)
    SCALED_DIMENSION(detailsWidth)
private:
    WInfoTokens* m_source;
};

class ScaledNexusTokens : public ScaledTokenGroup {
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit ScaledNexusTokens(NexusTokens* source, QObject* parent) : ScaledTokenGroup(source, parent), m_source(source) {}
    UNSCALED_VALUE(heightMult)
    UNSCALED_VALUE(ratio)
    SCALED_DIMENSION(minWidth)
    SCALED_DIMENSION(minHeight)
    SCALED_DIMENSION(maxNavWidth)
    SCALED_DIMENSION(maxContentWidth)
    SCALED_DIMENSION(popupWidth)
    SCALED_DIMENSION(minPopupHeight)
    SCALED_DIMENSION(maxPopupHeight)
    SCALED_DIMENSION(networkShowEthDetailWidth)
    SCALED_DIMENSION(networkShowVpnDetailWidth)
    SCALED_DIMENSION(maxDialogWidth)
    SCALED_DIMENSION(maxDialogHeight)
    SCALED_DIMENSION(textFieldWidth)
    SCALED_DIMENSION(smallTextFieldWidth)
private:
    NexusTokens* m_source;
};

#undef SCALED_DIMENSION
#undef UNSCALED_VALUE

class ScaledSizeTokens : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(hyprstack::config::ScaledBarTokens* bar READ bar CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledDashboardTokens* dashboard READ dashboard CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledLauncherTokens* launcher READ launcher CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledNotifsTokens* notifs READ notifs CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledOsdTokens* osd READ osd CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledSessionTokens* session READ session CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledSidebarTokens* sidebar READ sidebar CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledUtilitiesTokens* utilities READ utilities CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledLockTokens* lock READ lock CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledWInfoTokens* winfo READ winfo CONSTANT)
    Q_PROPERTY(hyprstack::config::ScaledNexusTokens* nexus READ nexus CONSTANT)
public:
    explicit ScaledSizeTokens(SizeTokens* source, QObject* parent) : QObject(parent)
        , m_bar(new ScaledBarTokens(source->bar(), this))
        , m_dashboard(new ScaledDashboardTokens(source->dashboard(), this))
        , m_launcher(new ScaledLauncherTokens(source->launcher(), this))
        , m_notifs(new ScaledNotifsTokens(source->notifs(), this))
        , m_osd(new ScaledOsdTokens(source->osd(), this))
        , m_session(new ScaledSessionTokens(source->session(), this))
        , m_sidebar(new ScaledSidebarTokens(source->sidebar(), this))
        , m_utilities(new ScaledUtilitiesTokens(source->utilities(), this))
        , m_lock(new ScaledLockTokens(source->lock(), this))
        , m_winfo(new ScaledWInfoTokens(source->winfo(), this))
        , m_nexus(new ScaledNexusTokens(source->nexus(), this)) {}

    [[nodiscard]] ScaledBarTokens* bar() const { return m_bar; }
    [[nodiscard]] ScaledDashboardTokens* dashboard() const { return m_dashboard; }
    [[nodiscard]] ScaledLauncherTokens* launcher() const { return m_launcher; }
    [[nodiscard]] ScaledNotifsTokens* notifs() const { return m_notifs; }
    [[nodiscard]] ScaledOsdTokens* osd() const { return m_osd; }
    [[nodiscard]] ScaledSessionTokens* session() const { return m_session; }
    [[nodiscard]] ScaledSidebarTokens* sidebar() const { return m_sidebar; }
    [[nodiscard]] ScaledUtilitiesTokens* utilities() const { return m_utilities; }
    [[nodiscard]] ScaledLockTokens* lock() const { return m_lock; }
    [[nodiscard]] ScaledWInfoTokens* winfo() const { return m_winfo; }
    [[nodiscard]] ScaledNexusTokens* nexus() const { return m_nexus; }

    void bindScale(AppearanceConfig* appearance) {
        if (m_appearance == appearance) return;
        QObject::disconnect(m_scaleConnection);
        m_appearance = appearance;
        m_scaleConnection = connect(appearance, &AppearanceConfig::scaleChanged, this, &ScaledSizeTokens::updateScale);
        updateScale();
    }
private:
    void updateScale() {
        const auto scale = m_appearance->effectiveScale();
        m_bar->setScale(scale);
        m_dashboard->setScale(scale);
        m_launcher->setScale(scale);
        m_notifs->setScale(scale);
        m_osd->setScale(scale);
        m_session->setScale(scale);
        m_sidebar->setScale(scale);
        m_utilities->setScale(scale);
        m_lock->setScale(scale);
        m_winfo->setScale(scale);
        m_nexus->setScale(scale);
    }
    AppearanceConfig* m_appearance = nullptr;
    QMetaObject::Connection m_scaleConnection;
    ScaledBarTokens* m_bar;
    ScaledDashboardTokens* m_dashboard;
    ScaledLauncherTokens* m_launcher;
    ScaledNotifsTokens* m_notifs;
    ScaledOsdTokens* m_osd;
    ScaledSessionTokens* m_session;
    ScaledSidebarTokens* m_sidebar;
    ScaledUtilitiesTokens* m_utilities;
    ScaledLockTokens* m_lock;
    ScaledWInfoTokens* m_winfo;
    ScaledNexusTokens* m_nexus;
};

} // namespace hyprstack::config
