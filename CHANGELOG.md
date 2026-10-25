# Изменения / Release notes

## 1.2.1 · 2026-10-25

- Быстрые действия в правой панели используют компактные кнопки одинакового
  размера. Подпись VPN находится рядом со значком; неполный ряд центрируется.
- Исправлено обрезание меню Bluetooth краем экрана после подключения устройства
  ([#4](https://github.com/hase9awa/hyprstack-shell/issues/4)). Ширина меню
  постоянна, статус переносится, длинное имя устройства сокращается.

English:

- Quick actions use equally sized compact buttons. The VPN caption sits beside
  its icon, and incomplete rows are centred.
- Fixed Bluetooth popout overflow after connecting a device
  ([#4](https://github.com/hase9awa/hyprstack-shell/issues/4)). The menu keeps
  a stable width, wraps its status text and elides long device names.

## 1.2.0 · 2026-10-24

- Встроено управление VPN через sing-box и Xray: профили, подписки, проверка
  задержки, TUN, локальный прокси и обход российских ресурсов. Работает одно
  сетевое ядро, без отдельного графического клиента.
- Добавлены окно VPN с кнопкой закрытия, доступ из настроек сети и включаемый
  значок на панели задач. В быстрых действиях кнопка подписана «VPN».
- Исправлен обход сайтов при отсутствии внешнего IPv6, включая доступ к ya.ru.
- Исправлены анимация и выравнивание стрелки компактного трея, а также раскрытие
  по клику при отключённом раскрытии наведением.
- Сохранён дополнительный патч Quickshell для повторного обнаружения значков,
  которые приложение объявило до готовности D-Bus объекта.
- Установка и обновление включают службу VPN и сохраняют пользовательские
  настройки. Версия согласована в интерфейсе, CLI, нативном модуле и Nix-пакете.

English:

- Added VPN controls using sing-box and Xray: profiles, subscriptions, latency
  checks, TUN, local proxies and Russian destination bypass. Only one core runs;
  a separate graphical client is unnecessary.
- Added a closeable VPN window, access from Network settings, an optional
  taskbar icon and a labelled VPN button in quick actions.
- Fixed destination bypass without upstream IPv6, including access to ya.ru.
- Fixed compact tray animation, chevron alignment and click expansion when
  hover expansion is disabled.
- Included an optional Quickshell patch to retry tray discovery when an
  application registers its item before its D-Bus object is ready.
- Installation and updates include the VPN service and preserve user settings.
  The UI, CLI, native extension and Nix package now report the same version.
