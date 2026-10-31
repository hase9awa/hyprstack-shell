[English](INSTALL.en.md) · [На главную](README.md) · [NixOS](INSTALL.nixos.md)

# Установка на Arch Linux и производные

<a id="arch"></a>

Arch Linux, CachyOS, EndeavourOS и Manjaro с systemd.
Нужны **Hyprland 0.57.0** с соответствующими заголовками, **Quickshell ≥ 0.3.1**
с Hyprland/PAM/Polkit и **Qt ≥ 6.9**. CMake проверяет ABI при сборке.

Модуль собирается строго для 0.57.0; после обновления с 0.56 завершите сеанс и войдите заново. См. [переход на 0.57](MAINTENANCE.md#переход-с-hyprland-056-на-057).

**Команды рассчитаны на Bash** — из Fish/Zsh сначала выполните `bash`.
Для существующей установки используйте [обновление](MAINTENANCE.md#обновление).

## 1. Зависимости

```bash
sudo pacman -Syu --needed base-devel git cmake ninja pkgconf gettext \
  hyprland quickshell nlohmann-json qt6-base qt6-declarative qt6-shadertools \
  qt6-svg qt6-imageformats qt6-wayland qt5ct qt6ct libqalculate lm_sensors \
  pixman libdrm libinput systemd-libs wayland libxkbcommon pango cairo \
  python python-pillow fuzzel wl-clipboard cliphist grim slurp wf-recorder \
  swappy libnotify brightnessctl networkmanager pipewire pipewire-audio \
  pipewire-pulse wireplumber polkit libcap hyprlock hyprpicker xdg-utils \
  xdg-user-dirs libxml2 adwaita-icon-theme dbus glib2 gsettings-desktop-schemas \
  xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
```

Терминал и браузер установите по своему выбору; Kitty и Firefox не обязательны.
Панель использует NetworkManager и PipeWire/WirePlumber —
[проверка служб](MAINTENANCE.md#сеть-и-звук).

## 2. Сборка и установка

```bash
git clone https://github.com/hase9awa/hyprstack-shell.git
cd hyprstack-shell
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DCMAKE_INSTALL_DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"
cmake --build build --parallel 2
cmake --install build
```

При нехватке памяти используйте `--parallel 1`.

<a id="config"></a>

## 3. Конфигурация

<details>
<summary>Если установка выполняется из работающего Hyprland</summary>

Перед копированием отключите автоматическое перечитывание конфига.
Для Lua-конфигурации:

```bash
hyprctl eval 'hl.config({misc={disable_autoreload=true}})'
```

Для прежней конфигурации `.conf`:

```bash
hyprctl keyword misc:disable_autoreload true
```

После настройки завершите сеанс и войдите заново. Копировать команды из TTY не нужно.

</details>

Из каталога исходников:

```bash
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$config_dir"/{hypr,hyprstack,systemd/user}
cp -a --backup=numbered shell/assets/hyprland/config/. "$config_dir/hypr/"
cp -a --backup=numbered distribution/defaults/hyprstack/. "$config_dir/hyprstack/"
cp -a --backup=numbered distribution/systemd/user/*.service "$config_dir/systemd/user/"
```

Копии `.~1~` создаются только при замене существующих файлов.
Укажите установленные приложения в скопированных конфигах:

- `hyprstack/hypr-vars.lua`: команды `terminal` и `browser`.
- `hyprstack/shell.json`: `general.apps.terminal`, например `["foot"]`.

[Примеры и параметры терминалов](CONFIGURATION.md#приложения-по-умолчанию).

## 4. Запуск

Завершите текущий сеанс и выберите **Hyprland** в менеджере входа.
Из TTY — `start-hyprland`. Основной конфиг — `~/.config/hypr/hyprland.lua`.

```bash
~/.local/bin/hyprstack-doctor
hyprctl configerrors
```

Оболочку автоматически запускает `hyprstack-session.service`; включать её вручную не нужно.
Если она не появилась — [диагностика автозапуска](MAINTENANCE.md#если-оболочка-не-запустилась).

[Настройки и клавиши](CONFIGURATION.md) · [Обновление](MAINTENANCE.md#обновление)
