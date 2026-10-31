[На главную](README.md) · [Установка](INSTALL.md)

# Обновление и восстановление

## Обновление

### Переход с Hyprland 0.56 на 0.57

Hyprstack 1.3.3 рассчитан на **Hyprland 0.57.0**. Нативный модуль необходимо
пересобрать: библиотека для 0.56.2 несовместима с новым рендерером и не загружается
с ошибкой `IPassElement::discard()`. Подробности —
[issue #5](https://github.com/hase9awa/hyprstack-shell/issues/5).

Обновите Hyprland вместе с зависимостями, завершите сеанс и выполните обычное
обновление Hyprstack из TTY. Затем войдите заново. Перезагрузка только shell или
`hyprctl reload` не заменяет работающий compositor. Старый `.so` копировать нельзя;
CMake и установщик проверяют соответствие заголовков установленному ABI.

После обновления `hyprstack-doctor` должен также подтвердить **Native plugin
loaded**. Сохранённые пути к старым `native/hyprstack-bars-*.so` внутри каталога
установки автоматически заменяются на актуальный `hyprstack-bars.so` при
загрузке. Внешние сборки и `HYPRSTACK_TITLEBAR_PLUGIN` остаются явными
переопределениями и требуют пересборки под текущий Hyprland.

Проверка сохранённого старого пути, ширины терминала, областей перерисовки,
точки захвата при перетаскивании, цветов заголовка и обратного перелёта Win+S
на двух выходах выполняется в отдельном вложенном сеансе. Кадровая проверка
подтверждает, что возвращающееся окно остаётся поверх активного окна:

```bash
HYPRSTACK_TEST_PREFIX=/путь/к/staged-prefix python3 distribution/tests/test_upgrade.py
```

Префикс должен содержать результат `cmake --install`; для проверки нужны
`kitty`, `grim`, Python Pillow и зависимости сборки проекта. На NVIDIA при ошибке выделения GBM-буфера вложенного сеанса можно
задать `GBM_BACKEND=nvidia-drm` для этой команды.

На NixOS обновите вход проекта целиком: Hyprland и модуль должны собираться из
одного набора пакетов.

### Arch Linux и производные

Завершите Hyprland, войдите в TTY (**Ctrl+Alt+F3**) и выполните без `sudo`:

```bash
cd /путь/к/hyprstack-shell
./update.sh
```

Скрипт получает исходники, проверяет ABI, собирает проект и обновляет файлы
с резервной копией. В `~/.config/hyprstack/` сохраняются пользовательские
JSON-файлы, `hypr-vars.lua` (переопределения стандартных биндов), `local.lua`
(дополнительные привязки и настройки) и `monitors.lua` (экраны).
Стандартные файлы в `~/.config/hypr/` и служебный `hyprstack/hypr-user.lua`
перезаписываются; текущая цветовая схема `hypr/scheme/current.lua` сохраняется.
Подробнее — [куда вносить пользовательские настройки](CONFIGURATION.md).

Служба `hyprstack-vpn.service` обновляется вместе с оболочкой. Профили VPN в
`${XDG_DATA_HOME:-$HOME/.local/share}/hyprstack/vpn/` и отдельно установленные
сетевые ядра сохраняются. Этот каталог содержит параметры серверов и пароли;
его не следует публиковать вместе с персональными настройками.

Если `update.sh` ещё нет в старом клоне, сначала выполните `git pull --ff-only`.

Опции: `--dry-run` — план изменений, `--jobs 1` — сборка с меньшим расходом памяти,
`--no-pull` — сборка текущих исходников. Свои изменения в Git сохраните
коммитом или через `git stash`.

После обновления войдите в Hyprland и выполните `hyprstack-doctor`.
Для отката снова завершите сеанс и запустите:

```bash
./update.sh --rollback
```

Копии: `${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-install/backups/`.
Откат не меняет системные пакеты. Версия Hyprland должна соответствовать
восстанавливаемой сборке; копия модуля для 0.56.2 не работает с 0.57.0.
Для конфигурации со ссылками на каталоги используйте свой менеджер dotfiles.

### NixOS и Home Manager

Из каталога конфигурации NixOS, заменив `YOUR_HOST`:

```bash
nix flake update hyprstack
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

Войдите в новый сеанс. Встроенный Home Manager применится вместе с системой.
Для отдельного Home Manager обновите тот же вход в его flake и выполните
`home-manager switch --flake .#YOUR_USER`. `update.sh` на NixOS не используется.

Без Home Manager обновите пользовательскую конфигурацию по
[отдельной инструкции NixOS](INSTALL.nixos.md#без-home-manager), указав
`data_dir=/run/current-system/sw/share/hyprstack` вместо каталога `result`.
Личные Lua/JSON-файлы сохраняются. Сборка CMake и копирование служб не нужны.

## Диагностика

```bash
hyprstack-doctor
hyprctl configerrors
hyprstack-doctor --json
journalctl --user -u hyprstack-session.service -b
```

`hyprstack-session.service` должна работать внутри сеанса Hyprland; её запускает
его конфигурация. `hyprstack-vpn.service` работает только при подключённом VPN.
Включать эти службы через `systemctl --user enable` не нужно.

Для запуска оболочки с выводом ошибок в терминал:

```bash
hyprstack-session stop
hyprstack-shell
```

- **QML:** проверьте совместимость Qt/Quickshell и наличие модулей `Hyprstack`
  и `M3Shapes`. После обновления Qt пересоберите Hyprstack и, если нужно, Quickshell.
- **PAM:** проверьте пакет `hyprlock` и `/etc/pam.d/hyprlock`.
- **Polkit:** остановите сторонний агент авторизации.
- **Пропадающие значки трея:** если приложение объявляет значок раньше готовности
  своего D-Bus объекта, для Quickshell доступен
  [патч повторного обнаружения](distribution/patches/quickshell-tray-retry.patch).
  Он подготовлен для коммита `11ca60be22b063478ed9586ca1d7f92f0f261caf`:
  в исходниках Quickshell выполните `git apply /путь/к/quickshell-tray-retry.patch`,
  затем пересоберите Quickshell с установленным Qt. CMake Hyprstack и установщик
  Gist сами этот патч к системному пакету не применяют.
- **VPN:** проверьте `journalctl --user -u hyprstack-vpn.service -b` и настройки
  сети. После замены ядра заново выдайте права кнопкой в окне VPN.

Перезапуск оболочки: `hyprstack-session restart`.

### Если оболочка не запустилась

```bash
hyprctl version
hyprctl configerrors
systemctl --user status hyprstack-session.service --no-pager
journalctl --user -u hyprstack-session.service -b --no-pager
```

Если `hyprctl version` не подключается к композитору, проверьте выбор сеанса
Hyprland в менеджере входа. Конфигурация проекта — `hypr/hyprland.lua`,
создавать `hyprland.conf` не нужно.

`hyprstack-session start` проверяет всю цепочку запуска службы.
Команда `hyprstack shell` запускает только интерфейс.

## Сеть и звук

Панель сети использует NetworkManager, звук — PipeWire/WirePlumber:

```bash
systemctl is-active NetworkManager.service
wpctl status
```

Если эти компоненты ещё не настроены, включите их:

```bash
sudo systemctl enable --now NetworkManager.service
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
```

При переходе с другого менеджера сети используйте
[инструкцию NetworkManager](https://wiki.archlinux.org/title/NetworkManager#Enable_NetworkManager).

## Восстановление прежнего окружения

На NixOS верните предыдущую ревизию конфигурации и примените её либо загрузите
прежнее поколение системы. Восстановите также конфигурацию Home Manager.
Изменяемые настройки пользователя возвращаются из резервной копии отдельно.

При ручном копировании заменённые файлы сохраняются рядом как `имя.~1~`,
`имя.~2~` и так далее. Завершите Hyprland и верните нужные версии файлов.

Для старых установок с каталогом `hyprstack-backup.*`:

1. Найдите копию `hyprstack-backup.*`, путь которой выведен при установке.
   Она находится в `${XDG_CONFIG_HOME:-$HOME/.config}` или домашнем каталоге.
   Если прежних конфигов не было, копия не создавалась и восстанавливать их не нужно.
2. Перенесите нынешние `hypr` и `hyprstack` из `${XDG_CONFIG_HOME:-$HOME/.config}`
   в отдельный каталог и верните туда прежние каталоги или ссылки из копии.
3. Верните сохранённые `systemd/user/hyprstack-session.service` и
   `systemd/user/hyprstack-vpn.service` в `systemd/user/`. В старых копиях они
   могли лежать в корне каталога копии. Если прежних служб не было, удалите установленные службы
   Hyprstack.
4. При наличии пользовательского systemd выполните `systemctl --user daemon-reload`
   и войдите в прежнее окружение.

## Удаление

Сначала отключите VPN и выполните `systemctl --user stop hyprstack-vpn.service`.
На Arch-based системах выданные через окно VPN сетевые права можно удалить
вместе с `/usr/local/lib/hyprstack-vpn/` и правилом
`/etc/polkit-1/rules.d/49-hyprstack-vpn-<UID>.rules` (нужны права администратора).

Перед удалением отключите **Обои и оформление → Цвета приложений →
Синхронизировать цвета приложений** и дождитесь применения: это восстановит
прежние параметры GTK, Qt и терминалов. Сохраняйте каталог
`hyprstack/theme-sync` в состоянии пользователя до завершения восстановления.

На NixOS отключите `programs.hyprstack.enable` в системной конфигурации
и Home Manager, удалите ненужные импорты и вход `hyprstack`, примените изменения.

На Arch-based системах восстановите прежнюю конфигурацию по разделу выше.
Установленные CMake файлы перечислены в `build/install_manifest.txt` вашей сборки;
просмотрите список и удалите указанные файлы Hyprstack.

Пользовательские данные удаляются по желанию:

| Каталог | Содержимое |
| --- | --- |
| `${XDG_CONFIG_HOME:-$HOME/.config}/hyprstack` | Настройки |
| `${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack` | Тема, обои, история и состояние |
| `${XDG_CACHE_HOME:-$HOME/.cache}/hyprstack` | Кеш изображений |
| `${XDG_DATA_HOME:-$HOME/.local/share}/hyprstack/vpn` | Приватные профили VPN |
| `${XDG_DATA_HOME:-$HOME/.local/share}/hyprstack/runtime/vpn` | Загруженные ядра VPN |
