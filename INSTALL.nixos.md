[English](INSTALL.nixos.en.md) · [На главную](README.md) · [Установка на Arch Linux](INSTALL.md)

# Установка Hyprstack на NixOS

Требуется конфигурация NixOS с flakes. Пакет Hyprstack использует совместимые
**Hyprland 0.56.2**, **Quickshell ≥ 0.3.1** и **Qt ≥ 6.9** из входов проекта.
Собирать проект через CMake и копировать пользовательские службы вручную не нужно.

Готовьте конфигурацию в текущем рабочем столе, пока доступна инструкция.
Ниже команды оболочки рассчитаны на **Bash**: при использовании Fish или Zsh
сначала выполните `bash`. Настройки flake вносите в свою существующую конфигурацию,
сохраняя остальные входы и модули.

## 1. Системный модуль

Добавьте вход `hyprstack` и модуль. Замените `YOUR_HOST` именем своей конфигурации:

```nix
{
  inputs.hyprstack.url = "github:hase9awa/hyprstack-shell";

  outputs = { nixpkgs, hyprstack, ... }: {
    nixosConfigurations.YOUR_HOST = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        hyprstack.nixosModules.default
        { programs.hyprstack.enable = true; }
      ];
    };
  };
}
```

Модуль предоставляет Hyprland, Quickshell, Qt, PAM и службы Hyprstack.
Не переопределяйте `programs.hyprland.package` другим пакетом: нативное расширение
должно совпадать с композитором по ABI.

Панель сети использует NetworkManager, звук — PipeWire/WirePlumber. Если они
ещё не настроены, добавьте в свой системный модуль:

```nix
{
  networking.networkmanager.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
}
```

При переходе с другого менеджера сети или звукового сервера согласуйте их
существующие настройки. Не настраивайте два менеджера для одного интерфейса.

Терминал, браузер и файловый менеджер устанавливаются по вашему выбору.
Конфигурация по умолчанию запускает Kitty и Firefox; если хотите использовать
именно их, добавьте в системный `environment.systemPackages` или пользовательский
`home.packages` пакеты `pkgs.kitty` и `pkgs.firefox`. Для других приложений до первого
входа измените `hyprstack/hypr-vars.lua` и `general.apps.terminal` в `shell.json`,
как описано в [настройках приложений](CONFIGURATION.md#приложения-по-умолчанию).

## 2. Пользовательская конфигурация

### С Home Manager

Если Home Manager уже подключён как модуль NixOS, добавьте в тот же список
`modules`, заменив `YOUR_USER` своим пользователем:

```nix
{
  home-manager.users.YOUR_USER = {
    imports = [ hyprstack.homeManagerModules.default ];
    programs.hyprstack.enable = true;
  };
}
```

Оба модуля должны использовать один вход `hyprstack`. Стандартная конфигурация
Hyprland управляется Home Manager; настройки интерфейса и пользовательские
Lua-файлы остаются доступными для редактирования.
Свои Lua-настройки можно также задать через
[`programs.hyprstack.extraConfig`](CONFIGURATION.md#экраны-и-клавиатура).

<details>
<summary>Если уже есть конфигурация Hyprland или Hyprstack</summary>

Для сохранения конфликтующих файлов при первой активации можно задать в модуле
NixOS [`home-manager.backupFileExtension`](https://nix-community.github.io/home-manager/usage/dotfiles.html)
со значением `"before-hyprstack"`.
Home Manager добавит этот суффикс к сохраняемым файлам. Если такой файл копии
уже существует, сначала перенесите его в отдельное место. На чистой установке
это не требуется. Свою конфигурацию, управляемую другим менеджером dotfiles,
сначала исключите из его управления.

</details>

## 3. Применение и первый запуск

Из каталога конфигурации NixOS:

```bash
sudo nixos-rebuild build --flake .#YOUR_HOST
```

### Без Home Manager

В работающем Hyprland перед копированием временно отключите автоперечитывание:
`hyprctl eval 'hl.config({misc={disable_autoreload=true}})'` для Lua
или `hyprctl keyword misc:disable_autoreload true` для `.conf`.

После сборки, до активации системы, скопируйте конфиги из `result`:

```bash
data_dir="$PWD/result/sw/share/hyprstack"
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$config_dir"/{hypr,hyprstack}
cp -rL --no-preserve=mode --backup=numbered "$data_dir/shell/assets/hyprland/config/." "$config_dir/hypr/"
cp -rL --no-preserve=mode --update=none "$data_dir/defaults/hyprstack/." "$config_dir/hyprstack/"
cp -L --no-preserve=mode "$data_dir/defaults/hyprstack/hypr-user.lua" "$config_dir/hyprstack/"
```

Файлы настроек остаются доступными для редактирования; уже существующие
Lua/JSON-настройки в `hyprstack/` сохраняются, кроме служебного `hypr-user.lua`.
[Выбор терминала и браузера](CONFIGURATION.md#приложения-по-умолчанию).
Службы устанавливает системный модуль.

### Активация

Если вы сейчас в Hyprland, завершите сеанс перед активацией и выполните
следующую команду в TTY из того же каталога. В другом рабочем столе её можно
выполнить сразу:

```bash
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

С Home Manager пользовательские конфиги применятся вместе с системой.
Войдите в новый сеанс **Hyprland** через менеджер входа
или `start-hyprland` из TTY.

Проверка в терминале нового сеанса:

```bash
hyprstack-doctor
hyprctl configerrors
wpctl status
nmcli general status
```

`hyprstack-session.service` запускается конфигурацией Hyprland; включать её
вручную не нужно. `hyprstack-vpn.service` запускается кнопкой подключения и
остаётся остановленной при выключенном VPN. Панель, уведомления, блокировка
и Polkit входят в сеанс Hyprstack. Отключите отдельный автозапуск прежних
аналогов в Hyprland, если он был настроен.

[Настройки и клавиши](CONFIGURATION.md) · [Обновление и восстановление](MAINTENANCE.md#nixos-и-home-manager)
