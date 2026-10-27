[Русский](INSTALL.md) · [Home](README.en.md) · [NixOS](INSTALL.nixos.en.md)

# Installing on Arch Linux and derivatives

<a id="arch"></a>

Arch Linux, CachyOS, EndeavourOS and Manjaro with systemd.
Requires **Hyprland 0.56.2** with matching headers, **Quickshell ≥ 0.3.1**
with Hyprland/PAM/Polkit, and **Qt ≥ 6.9**. CMake checks the ABI during the build.

**Commands assume Bash** — run `bash` first if you use Fish/Zsh.
For an existing installation, use the [update procedure](MAINTENANCE.md#обновление).

## 1. Dependencies

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

Install your preferred terminal and browser; Kitty and Firefox are optional.
The panel uses NetworkManager and PipeWire/WirePlumber —
[service checks](MAINTENANCE.md#сеть-и-звук).

## 2. Build and install

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

Use `--parallel 1` if memory is limited.

<a id="config"></a>

## 3. Configuration

<details>
<summary>If you are installing from a running Hyprland session</summary>

Disable automatic configuration reload before copying files.
For a Lua configuration:

```bash
hyprctl eval 'hl.config({misc={disable_autoreload=true}})'
```

For a previous `.conf` configuration:

```bash
hyprctl keyword misc:disable_autoreload true
```

Log out after configuration and log in again. No configuration commands need to be entered in a TTY.

</details>

From the source directory:

```bash
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$config_dir"/{hypr,hyprstack,systemd/user}
cp -a --backup=numbered shell/assets/hyprland/config/. "$config_dir/hypr/"
cp -a --backup=numbered distribution/defaults/hyprstack/. "$config_dir/hyprstack/"
cp -a --backup=numbered distribution/systemd/user/*.service "$config_dir/systemd/user/"
```

Backups named `.~1~` are created only when replacing existing files.
Set your installed applications in the copied configuration:

- `hyprstack/hypr-vars.lua`: the `terminal` and `browser` commands.
- `hyprstack/shell.json`: `general.apps.terminal`, for example `["foot"]`.

[Examples and terminal arguments](CONFIGURATION.md#приложения-по-умолчанию).

## 4. Launch

Log out and select **Hyprland** in your display manager.
From a TTY, run `start-hyprland`. The main configuration is `~/.config/hypr/hyprland.lua`.

```bash
~/.local/bin/hyprstack-doctor
hyprctl configerrors
```

`hyprstack-session.service` starts the shell automatically; do not enable it manually.
If the shell does not appear, see [startup diagnostics](MAINTENANCE.md#если-оболочка-не-запустилась).

[Configuration and shortcuts](CONFIGURATION.md) · [Updates](MAINTENANCE.md#обновление)
