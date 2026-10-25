# Сторонние компоненты и лицензии

Hyprstack 1.2.1 включает изменённый код перечисленных проектов. Интерфейс и
имена компонентов используют Hyprstack; исходные названия ниже сохраняют
указание авторства. Дата изменений: 25.10.2026.

| Компонент | Источник | Лицензия | Локальный файл лицензии |
| --- | --- | --- | --- |
| Оболочка и нативные модули QML, на основе Caelestia shell 2.5.0 | https://github.com/caelestia-dots/shell | GPL-3.0 | `shell/LICENSE` |
| Нативные декорации окон, изменённый hyprbars | https://github.com/hyprwm/hyprland-plugins/tree/7644cecdb947060682891a0db2a0cdc5c0b9e704/hyprbars | BSD-3-Clause | `native/hyprbars/LICENSE` |
| M3Shapes, коммит `8a6fe8961749887d677700b6508e0c9249968b7e` | https://github.com/soramanew/m3shapes | Apache-2.0 | `third_party/m3shapes/LICENSE` |
| Google Sans Flex | https://github.com/googlefonts/google-sans-flex | SIL OFL-1.1 | `shell/assets/google-sans-flex/LICENSE` |
| Material Symbols Rounded | https://github.com/google/material-design-icons | Apache-2.0 | `shell/assets/material-symbols/LICENSE` |

Исходники включённых нативных библиотек предоставляются в этой поставке.
Изменения включают оформление и названия Hyprstack, команды управления рабочим
столом, запуск и завершение сеанса, стандартную конфигурацию, размещение окон и
обзор, историю уведомлений, цветовые темы, кэширование изображений, управление
ресурсами и русский перевод с переключением языка.

Логотип в `shell/assets/logo.svg` и `shell/components/Logo.qml` — собственный
дизайн под лицензией проекта. Шрифты сохраняют свои отдельные лицензии.
Зависимости из репозиториев дистрибутива остаются отдельными проектами
со своими лицензиями.

В `distribution/patches/quickshell-tray-retry.patch` сохранены изменения
обнаружения значков для Quickshell на базе коммита
`11ca60be22b063478ed9586ca1d7f92f0f261caf`. Полный Quickshell не включён
в исходники Hyprstack; лицензия — [LGPL-3.0](https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/LICENSE).

Встроенные палитры сохраняют исходные значения RGB и названия цветов.
Проекты-источники и адаптации режимов перечислены в
[источниках палитр](shell/assets/schemes/SOURCES.md).

Кадры и короткая запись интерфейса находятся в `docs/media/` и не устанавливаются
вместе с оболочкой. Сведения об изображениях, видимых в записи, приведены в
[описании демонстрации](docs/media/README.md).

VPN запускает отдельно устанавливаемые официальные ядра
[sing-box](https://github.com/SagerNet/sing-box) (GPL-3.0-or-later с исключениями проекта)
и [Xray-core](https://github.com/XTLS/Xray-core) (MPL-2.0).
Собственный графический клиент этих проектов не распространяется.
Правила маршрутизации загружаются из
[russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat).
