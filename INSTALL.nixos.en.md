[Русский](INSTALL.nixos.md) · [Home](README.en.md) · [Arch Linux installation](INSTALL.en.md)

# Installing Hyprstack on NixOS

Requires a NixOS configuration using flakes. Hyprstack uses matching
**Hyprland 0.56.2**, **Quickshell ≥ 0.3.1** and **Qt ≥ 6.9** from the project's
inputs. No manual CMake build or copying user service files is needed.

Prepare your configuration in your current desktop while this guide is available.
Shell commands below assume **Bash**: run `bash` first if you use Fish or Zsh.
Merge the flake entries into your existing configuration, keeping other inputs
and modules.

## 1. System module

Add the `hyprstack` input and module. Replace `YOUR_HOST` with your configuration name:

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

The module provides Hyprland, Quickshell, Qt, PAM and the Hyprstack services.
Do not override `programs.hyprland.package` with another package: the native
extension must match the compositor's ABI.

The network panel uses NetworkManager, and audio uses PipeWire/WirePlumber.
If they are not configured yet, add to your system module:

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

When switching from another network manager or audio server, reconcile their
existing configuration. Do not configure two managers for the same interface.

Install your preferred terminal, browser and file manager separately.
The default configuration launches Kitty and Firefox; to use them, add
`pkgs.kitty` and `pkgs.firefox` to your system `environment.systemPackages` or
user `home.packages`. For other applications, edit `hyprstack/hypr-vars.lua`
and `general.apps.terminal` in `shell.json` before the first login, as described
in [application settings (Russian)](CONFIGURATION.md#приложения-по-умолчанию).

## 2. User configuration

### With Home Manager

If Home Manager is already integrated into NixOS, add this to the same
`modules` list, replacing `YOUR_USER` with your username:

```nix
{
  home-manager.users.YOUR_USER = {
    imports = [ hyprstack.homeManagerModules.default ];
    programs.hyprstack.enable = true;
  };
}
```

Both modules must use the same `hyprstack` input. Home Manager manages the
standard Hyprland configuration, while interface preferences and user Lua files
remain editable. You can also supply custom Lua using
[`programs.hyprstack.extraConfig`](CONFIGURATION.md#экраны-и-клавиатура).

<details>
<summary>If you already have Hyprland or Hyprstack configuration</summary>

To preserve conflicting files during first activation, you can set
[`home-manager.backupFileExtension`](https://nix-community.github.io/home-manager/usage/dotfiles.html)
to `"before-hyprstack"` in your NixOS module.
Home Manager appends this suffix to the saved files. If a backup with that name
already exists, move it elsewhere first. A clean installation does not need this.
If another dotfiles manager controls your configuration, remove it from that
manager first.

</details>

## 3. Apply and launch

From your NixOS configuration directory:

```bash
sudo nixos-rebuild build --flake .#YOUR_HOST
```

### Without Home Manager

In a running Hyprland session, disable automatic reload before copying:
`hyprctl eval 'hl.config({misc={disable_autoreload=true}})'` for Lua,
or `hyprctl keyword misc:disable_autoreload true` for `.conf`.

After building, copy configuration from `result` before activating the system:

```bash
data_dir="$PWD/result/sw/share/hyprstack"
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$config_dir"/{hypr,hyprstack}
cp -rL --no-preserve=mode --backup=numbered "$data_dir/shell/assets/hyprland/config/." "$config_dir/hypr/"
cp -rL --no-preserve=mode --update=none "$data_dir/defaults/hyprstack/." "$config_dir/hyprstack/"
cp -L --no-preserve=mode "$data_dir/defaults/hyprstack/hypr-user.lua" "$config_dir/hyprstack/"
```

Copied preferences stay writable. Existing Lua/JSON preferences in `hyprstack/`
are preserved, except for the managed `hypr-user.lua` entry.
[Choose your terminal and browser](CONFIGURATION.md#приложения-по-умолчанию).
The system module provides the services.

### Activation

If you currently use Hyprland, end the session before activation and run the next
command in a TTY from the same directory. In another desktop, you can run it immediately:

```bash
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

With Home Manager, user configuration is applied with the system. Start a new
**Hyprland** session through your display manager or `start-hyprland` in a TTY.

Run in a terminal in the new session:

```bash
hyprstack-doctor
hyprctl configerrors
wpctl status
nmcli general status
```

The Hyprland configuration starts `hyprstack-session.service`; do not enable it
manually. The VPN connect button starts `hyprstack-vpn.service`, which stays
inactive when VPN is off. The panel, notifications, lock screen and Polkit agent
are part of the Hyprstack session. Disable any separately configured autostart
of previous equivalents in Hyprland.

[Configuration and shortcuts (Russian)](CONFIGURATION.md) ·
[Updates and recovery (Russian)](MAINTENANCE.md#nixos-и-home-manager)
