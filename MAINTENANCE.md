[На главную](README.md) · [Установка](INSTALL.md)

# Обновление и восстановление

## Обновление

Поддерживаются **Hyprland 0.57.0 и 0.57.1**. После обновления Hyprland
пересоберите Hyprstack по инструкции ниже: нативный модуль зависит от его версии.

### Arch Linux и производные

Через **Настройки → Обновления** или одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/hase9awa/hyprstack-shell/main/update.sh | bash
```

С версии 1.4.11 достаточно `hyprstack-update`.

Сохраните работу: установка завершит сеанс Hyprland после подтверждения.
Личные настройки сохраняются, резервная копия создаётся автоматически.

<details>
<summary>Ручная сборка и откат</summary>

После выхода из Hyprland, из каталога исходников:

```bash
./update.sh --no-pull
```

Откат из TTY:

```bash
hyprstack-update rollback
```

Версия Hyprland должна соответствовать восстанавливаемой сборке.

</details>

### NixOS и Home Manager

Раздел **Настройки → Обновления** проверяет релизы и показывает уведомления;
установка выполняется через конфигурацию NixOS/Home Manager.

Из каталога конфигурации NixOS, заменив `YOUR_HOST`:

```bash
nix flake update hyprstack
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

Войдите в новый сеанс. Встроенный Home Manager применится вместе с системой.
Для отдельного Home Manager обновите вход `hyprstack` в его flake и выполните
`home-manager switch --flake .#YOUR_USER`.

Без Home Manager следуйте [инструкции NixOS](INSTALL.nixos.md#без-home-manager),
указав `data_dir=/run/current-system/sw/share/hyprstack`. `update.sh` на NixOS не используется.

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
