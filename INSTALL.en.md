[Русский](INSTALL.md) · [Home](README.en.md) · [NixOS installation](INSTALL.nixos.en.md)

# Installing Hyprstack on Arch Linux and derivatives

<a id="arch"></a>

For Arch Linux, CachyOS, EndeavourOS and Manjaro with systemd.
Hyprstack installs the shell and Hyprland configuration for your user.
Choose your own terminal, browser and file manager.

Run the installation in your current desktop's terminal, keeping this guide open
in your browser. Log out after configuration, before starting Hyprstack.
If Hyprland is already running, the setup script prepares a separate command
to apply the configuration after logout; see step 4.

**All commands in this guide assume Bash.** If you use Fish, Zsh or another shell,
start Bash in your current terminal first:

```sh
bash
```

Your login shell stays the same. Run commands **without `sudo`**, except package
installation and enabling the system network service.

## 1. Dependencies

Requires **Hyprland 0.56.2**, **Quickshell ≥ 0.3.1** with Hyprland, PAM and
Polkit modules, and **Qt ≥ 6.9**. Build requirements: C++23, CMake ≥ 3.22,
Python ≥ 3.10. Hyprland headers must match the installed compositor's ABI.
Check the repository versions:

```bash
pacman -Si hyprland quickshell qt6-base
```

Continue only if Hyprland **0.56.2** is available and the requirements above
are met. If your distribution branch provides other versions, prepare a
compatible package set first. Do not bypass the ABI check.

Update the system and install build and desktop feature dependencies:

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

`fuzzel` provides emoji and clipboard selection, `grim`/`slurp`/`swappy` handle
screenshots, and `wf-recorder` records the screen. `qt5ct`/`qt6ct` and desktop
portals provide application appearance and desktop integration.
To change colours in running KDE applications, you can use
[qt6ct-kde](https://aur.archlinux.org/packages/qt6ct-kde) instead of `qt6ct`.

**Install personal applications separately, according to your preferences.**
Use your existing terminal and browser if they are already installed.
For example, to install Foot and Chromium:

```bash
sudo pacman -S --needed foot chromium
```

Kitty and Firefox also work, but Hyprstack does not require them.
The file manager uses your system's `xdg-open` association.
`pavucontrol` is only needed for **Ctrl+Alt+V**, and `btop` for
**Ctrl+Shift+Escape**; install them if you want those actions.

## 2. Build

```bash
git clone https://github.com/hase9awa/hyprstack-shell.git
cd hyprstack-shell
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DCMAKE_INSTALL_DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"
cmake --build build --parallel 2
cmake --install build
export PATH="$HOME/.local/bin:$PATH"
```

Use `--parallel 1` if memory is limited. Programs go into `~/.local/bin`,
and data into your user's XDG data directory.

Add `~/.local/bin` to your login profile's `PATH` if it is not there already:

| Login shell | Setting |
| --- | --- |
| Bash | Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bash_profile` |
| Zsh | Add the same line to `~/.zprofile` |
| Fish | Run from the current Bash shell: `fish -c 'fish_add_path "$HOME/.local/bin"'` |

## 3. Network and audio

The network panel uses **NetworkManager**; audio uses **PipeWire/WirePlumber**.
Check your existing setup first:

```bash
systemctl is-active NetworkManager.service
wpctl status
```

If these components already provide working network and audio, proceed to step 4.
On a fresh system without a configured network manager, enable NetworkManager:

```bash
sudo systemctl enable --now NetworkManager.service
```

If another manager controls your network interface, follow the
[NetworkManager migration instructions](https://wiki.archlinux.org/title/NetworkManager#Enable_NetworkManager)
first. Two managers must not control the same interface.

PipeWire uses user services and socket activation. If you have just installed
its packages, retry `wpctl status` after the first login in step 5. If it still
cannot connect, run as your regular user:

```bash
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
```

See [PipeWire](https://wiki.archlinux.org/title/PipeWire#Installation) and
[running WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/daemon/running.html).

<a id="config"></a>

## 4. First configuration

While still in your current desktop, run from the source directory:

```bash
bash configure.sh
```

The script asks for the commands of your **installed** terminal and browser.
Press Enter to accept a suggestion, or enter your own choice. The terminal choice
applies to **Super+Enter**, terminal applications launched from the menu and
the system monitor. You can also provide your choices directly; for Foot and Chromium:

```bash
bash configure.sh --terminal foot --browser chromium
```

The script installs `hypr/`, `hyprstack/`, initial colours and two user services.
Existing configurations are saved under `~/.config/hyprstack-backup.*`; the script
prints the exact path. If you use a custom `XDG_CONFIG_HOME`, the backup goes
there instead. **A clean installation does not create a backup.**
Use [update.sh](MAINTENANCE.md#обновление) for later updates: repeating first setup
replaces the entire configuration.

**If Hyprland is already running**, the script saves your application choices
and XDG paths for use after logout. End your session, log into a TTY
(**Ctrl+Alt+F3**) and run just this command:

```bash
bash ~/.local/state/hyprstack-setup/apply.sh
```

No source-directory navigation, remembered variables or copied command blocks
are needed. Switching to a TTY while leaving Hyprland running is insufficient:
the script does not replace a running compositor's configuration.
You can also prepare this command explicitly with `bash configure.sh --prepare`.

## 5. First launch and checks

After the configuration is ready, log out of your current desktop and choose
**Hyprland** in your display manager. Without a display manager, log into a TTY
and run `start-hyprland`.

In the new session, **Super+Enter** opens your selected terminal, **Super+W**
opens the browser and **Super+D** opens the application menu. Run:

```bash
~/.local/bin/hyprstack-doctor
hyprctl configerrors
```

Diagnostics should finish without `FAIL`, and `hyprctl configerrors` should
report no errors. If the panel does not appear:

```bash
systemctl --user status hyprstack-session.service
journalctl --user -u hyprstack-session.service -b
```

### What starts automatically

| Component | Started by | Manual enable needed? |
| --- | --- | --- |
| NetworkManager | System systemd | Once, if networking is not configured; step 3 |
| PipeWire and WirePlumber | User systemd | Usually ready after installation; check in step 3 |
| `hyprstack-session.service` | Hyprland configuration at login | No; no `enable` or extra autostart entry |
| `hyprstack-vpn.service` | VPN connect button | No; an inactive service is normal when VPN is off |
| Panel, notifications, lock screen, Polkit agent | Hyprstack session | No separate services to install |

If separate user services start your previous panel, notification daemon or
Polkit agent, disable their autostart in the Hyprland session. Do not add second
instances of these components to the new configuration.

## Optional features

| Package | Purpose |
| --- | --- |
| `bluez` | Bluetooth; after installation run `sudo systemctl enable --now bluetooth.service` |
| `upower` | Battery information |
| `power-profiles-daemon` | Power profiles; `sudo systemctl enable --now power-profiles-daemon.service` |
| `ddcutil` | External monitor brightness over DDC/CI |
| `wtype` | Type emoji into the active application |

Theme synchronization supports terminals including Kitty and Foot.
**Fish is a command shell running inside a terminal**: the terminal supplies
its background and ANSI palette, while Fish syntax highlighting and prompt
themes are configured separately.
[Supported applications and limitations (Russian)](CONFIGURATION.md#цвета-терминала-и-командная-оболочка).

Configure VPN under **Settings → Network → VPN settings**. sing-box/Xray cores
are downloaded when needed; TUN requires a one-time Polkit authorization.
[Protocols, imports and routing (Russian)](CONFIGURATION.md#vpn-и-прокси).

[Configuration and shortcuts (Russian)](CONFIGURATION.md) ·
[Updates and diagnostics (Russian)](MAINTENANCE.md)
