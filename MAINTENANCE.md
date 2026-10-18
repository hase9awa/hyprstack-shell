[На главную](README.md) · [Установка](INSTALL.md)

# Обновление и восстановление

## Обновление

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
Откат не меняет системные пакеты; требуется Hyprland **0.56.2**.
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
[инструкции](INSTALL.md#config), затем верните личные Lua/JSON-файлы из копии.
Сборку CMake и копирование службы пропустите.

## Диагностика

```bash
hyprstack-doctor
hyprctl configerrors
hyprstack-doctor --json
journalctl --user -u hyprstack-session.service -b
```

Для запуска оболочки с выводом ошибок в терминал:

```bash
hyprstack-session stop
hyprstack-shell
```

- **QML:** проверьте совместимость Qt/Quickshell и наличие модулей `Hyprstack`
  и `M3Shapes`. После обновления Qt пересоберите Hyprstack и, если нужно, Quickshell.
- **PAM:** проверьте пакет `hyprlock` и `/etc/pam.d/hyprlock`.
- **Polkit:** остановите сторонний агент авторизации.

Перезапуск оболочки: `hyprstack-session restart`.

## Восстановление прежнего окружения

На NixOS верните предыдущую ревизию конфигурации и примените её либо загрузите
прежнее поколение системы. Восстановите также конфигурацию Home Manager.
Изменяемые настройки пользователя возвращаются из резервной копии отдельно.

Без Home Manager завершите Hyprland и перейдите в TTY:

1. Найдите `hyprstack-backup.*`, выведенный при установке.
2. Перенесите нынешние `hypr` и `hyprstack` из `${XDG_CONFIG_HOME:-$HOME/.config}`
   в отдельный каталог и верните туда прежние каталоги или ссылки из копии.
3. Верните сохранённый `hyprstack-session.service` в `systemd/user/`.
   Если прежней службы не было, удалите только установленную службу Hyprstack.
4. При наличии пользовательского systemd выполните `systemctl --user daemon-reload`
   и войдите в прежнее окружение.

## Удаление

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
