#pragma once

#include <qquickattachedpropertypropagator.h>

#include "rootnodes.hpp"

namespace hyprstack::config {

class Config : public QQuickAttachedPropertyPropagator, public QQmlParserStatus {
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT
    QML_UNCREATABLE("")
    QML_ATTACHED(Config)

    Q_PROPERTY(QString screen READ screen WRITE inheritScreen NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::AppearanceConfig* appearance READ appearance NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::GeneralConfig* general READ general NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::BackgroundConfig* background READ background NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::BarConfig* bar READ bar NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::BorderConfig* border READ border NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::DashboardConfig* dashboard READ dashboard NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::LauncherConfig* launcher READ launcher NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::LockConfig* lock READ lock NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::NexusConfig* nexus READ nexus NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::NotifsConfig* notifs READ notifs NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::OsdConfig* osd READ osd NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::PointerConfig* pointer READ pointer NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::ServiceConfig* services READ services NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::SessionConfig* session READ session NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::SidebarConfig* sidebar READ sidebar NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::UtilitiesConfig* utilities READ utilities NOTIFY sourceChanged)
    Q_PROPERTY(const hyprstack::config::UserPaths* paths READ paths NOTIFY sourceChanged)

public:
    explicit Config(QObject* parent = nullptr);

    [[nodiscard]] QString screen() const;
    void inheritScreen(const QString& screen);

    [[nodiscard]] const AppearanceConfig* appearance() const;
    [[nodiscard]] const GeneralConfig* general() const;
    [[nodiscard]] const BackgroundConfig* background() const;
    [[nodiscard]] const BarConfig* bar() const;
    [[nodiscard]] const BorderConfig* border() const;
    [[nodiscard]] const DashboardConfig* dashboard() const;
    [[nodiscard]] const LauncherConfig* launcher() const;
    [[nodiscard]] const LockConfig* lock() const;
    [[nodiscard]] const NexusConfig* nexus() const;
    [[nodiscard]] const NotifsConfig* notifs() const;
    [[nodiscard]] const OsdConfig* osd() const;
    [[nodiscard]] const PointerConfig* pointer() const;
    [[nodiscard]] const ServiceConfig* services() const;
    [[nodiscard]] const SessionConfig* session() const;
    [[nodiscard]] const SidebarConfig* sidebar() const;
    [[nodiscard]] const UtilitiesConfig* utilities() const;
    [[nodiscard]] const UserPaths* paths() const;

    [[nodiscard]] Q_INVOKABLE static ConfigRoot* forScreen(const QString& screen);

    static Config* qmlAttachedProperties(QObject* object);

    void classBegin() override;
    void componentComplete() override;

signals:
    void sourceChanged();

protected:
    void attachedParentChange(
        QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) override;

private:
    void propagateScreen();

    bool m_complete = false;
    QString m_screen;
    ConfigRoot* m_config = nullptr;
};

} // namespace hyprstack::config
