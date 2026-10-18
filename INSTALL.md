[English](INSTALL.en.md) · [На главную](README.md)

# Установка Hyprstack

[Arch Linux и производные](#arch) · [NixOS](#nixos)

Требуются **Hyprland 0.56.2**, **Quickshell ≥ 0.3.1** с модулями Hyprland,
PAM и Polkit, **Qt ≥ 6.9**. Для сборки: C++23, CMake ≥ 3.22, Python ≥ 3.10.
Заголовки Hyprland должны совпадать с установленным композитором по ABI.

<a id="arch"></a>

## Arch Linux / CachyOS / EndeavourOS / Manjaro

### 1. Зависимости

Проверьте версии в репозиториях. Продолжайте, только если доступен Hyprland
**0.56.2** и выполнены требования выше:

```bash
pacman -Si hyprland quickshell qt6-base
```

```bash
sudo pacman -Syu --needed base-devel git cmake ninja pkgconf gettext \
  hyprland quickshell nlohmann-json qt6-base qt6-declarative qt6-shadertools \
  qt6-svg qt6-imageformats qt6-wayland qt5ct qt6ct libqalculate lm_sensors \
  pixman libdrm libinput systemd-libs wayland libxkbcommon pango cairo \
  python python-pillow kitty firefox fuzzel btop pavucontrol \
  wl-clipboard cliphist grim slurp wf-recorder swappy libnotify \
  brightnessctl networkmanager pipewire pipewire-pulse wireplumber \
  polkit hyprlock hyprpicker xdg-utils xdg-user-dirs libxml2 adwaita-icon-theme dbus \
  glib2 gsettings-desktop-schemas xdg-desktop-portal-gtk
```

Для обновления цветов уже открытых Dolphin и других KDE-приложений вместо
`qt6ct` используйте [qt6ct-kde](https://aur.archlinux.org/packages/qt6ct-kde).
Обычный `qt6ct` применяет KDE-схему при следующем запуске приложения.

### 2. Сборка

Выполняйте без `sudo`:

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

При нехватке памяти замените `--parallel 2` на `--parallel 1`.

<a id="config"></a>

### 3. Конфигурация

Завершите графический сеанс, войдите в TTY (**Ctrl+Alt+F3**) и вернитесь
в каталог исходников. Команды рассчитаны на Bash; XDG-пути должны совпадать
с путями графического сеанса.

<a id="backup"></a>

Перенесите прежнюю конфигурацию в резервную копию:

```bash
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
backup_dir=$(mktemp -d "$HOME/hyprstack-backup.XXXXXXXX")
for name in hypr hyprstack systemd/user/hyprstack-session.service; do
    if [ -e "$config_dir/$name" ] || [ -L "$config_dir/$name" ]; then
        mv "$config_dir/$name" "$backup_dir/"
    fi
done
printf 'Резервная копия: %s\n' "$backup_dir"
```

Сохраните выведенный путь. Затем скопируйте новую конфигурацию:

```bash
mkdir -p "$config_dir/hypr" "$config_dir/hyprstack"
cp -R shell/assets/hyprland/config/. "$config_dir/hypr/"
cp -R distribution/defaults/hyprstack/. "$config_dir/hyprstack/"
export PATH="$HOME/.local/bin:$PATH"
hyprstack scheme set -n hyprstack-catppuccin -m dark
```

**Только для Arch-based систем:** установите пользовательскую службу.
На NixOS её предоставляет модуль — этот блок пропустите.

```bash
mkdir -p "$config_dir/systemd/user"
cp distribution/systemd/user/hyprstack-session.service "$config_dir/systemd/user/"
systemctl --user daemon-reload
```

Без пользовательского systemd пропустите этот блок: оболочка использует
встроенный менеджер сеанса. Добавьте `~/.local/bin` в `PATH` своего профиля входа.

### 4. Запуск

Войдите в Hyprland через менеджер входа или `start-hyprland` из TTY.
В терминале выполните:

```bash
hyprstack-doctor
hyprctl configerrors
```

<a id="nixos"></a>

## NixOS

### 1. Системный модуль

Добавьте в существующий `flake.nix`, сохранив остальные входы и модули.
Замените `YOUR_HOST` именем своей конфигурации:

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

Модуль устанавливает совместимые Hyprland, Quickshell, Qt, PAM и службу оболочки.
Не переопределяйте `programs.hyprland.package` другим пакетом.

### 2. Пользовательская конфигурация

Если Home Manager уже подключён, выйдите из графического сеанса и выполните
**только блок [резервного копирования](#backup)**. Добавьте в тот же список
`modules`, заменив `YOUR_USER` своим пользователем:

```nix
{
  home-manager.users.YOUR_USER = {
    imports = [ hyprstack.homeManagerModules.default ];
    programs.hyprstack.enable = true;
  };
}
```

Оба модуля должны использовать один вход `hyprstack`. Настройки оболочки
останутся доступны для изменения через интерфейс.
Свои Lua-настройки: [`programs.hyprstack.extraConfig`](CONFIGURATION.md#экраны-и-клавиатура)
или `~/.config/hyprstack/local.lua`.

**Без Home Manager:** пропустите этот пункт; после применения системы
скопируйте конфигурацию, как описано ниже.

### 3. Применение

Из каталога конфигурации NixOS:

```bash
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

<details>
<summary>Копирование конфигурации без Home Manager</summary>

Из TTY получите файлы и выполните [пункт 3 для Arch](#config),
**пропустив блок пользовательской службы**. Сборка CMake не нужна.

```bash
git clone https://github.com/hase9awa/hyprstack-shell.git
cd hyprstack-shell
```

</details>

Войдите в новый сеанс Hyprland и выполните `hyprstack-doctor`
и `hyprctl configerrors`.

## Службы и дополнительные пакеты

Для сети нужен NetworkManager, для звука — PipeWire/WirePlumber; службы должны
быть включены в вашей системе. Отключите автозапуск прежней панели, демона
уведомлений и стороннего агента Polkit.

По необходимости: `bluez` — Bluetooth, `upower` — батарея,
`power-profiles-daemon` — профили питания, `ddcutil` — яркость внешних экранов,
`wtype` — ввод emoji. Файловый менеджер выберите самостоятельно.

[Настройки и клавиши](CONFIGURATION.md) · [Обновление и диагностика](MAINTENANCE.md)
