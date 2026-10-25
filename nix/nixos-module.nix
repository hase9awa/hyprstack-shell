self: { config, lib, pkgs, ... }:
let
  cfg = config.programs.hyprstack;
  package = cfg.package;
in {
  options.programs.hyprstack = {
    enable = lib.mkEnableOption "Hyprstack and its matching Hyprland session";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "Hyprstack package, including its matching compositor and Quickshell.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = toString config.programs.hyprland.package == toString package.hyprland;
      message = "Hyprstack's native module must use the same Hyprland package as the system session.";
    }];

    programs.hyprland.enable = true;
    programs.hyprland.package = lib.mkDefault package.hyprland;
    programs.hyprlock.enable = true;
    environment.systemPackages = [ package ];

    # The shell answers appearance settings, file dialogs and permission
    # prompts itself, so applications follow its theme without gsettings and
    # ask through its own dialogs. Every other interface, screen sharing
    # included, keeps the backend the session already uses.
    xdg.portal.enable = lib.mkDefault true;
    xdg.portal.extraPortals = [ package ];
    xdg.portal.config.hyprland = {
      "org.freedesktop.impl.portal.Settings" = lib.mkDefault [ "hyprstack" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = lib.mkDefault [ "hyprstack" "gtk" ];
      "org.freedesktop.impl.portal.Access" = lib.mkDefault [ "hyprstack" "gtk" ];
      "org.freedesktop.impl.portal.AppChooser" = lib.mkDefault [ "hyprstack" "gtk" ];
      "org.freedesktop.impl.portal.Wallpaper" = lib.mkDefault [ "hyprstack" "gtk" ];
    };

    environment.sessionVariables = {
      HYPRSTACK_DATA_DIR = "${package}/share/hyprstack";
      HYPRSTACK_SESSION_COMMAND = "${package}/bin/hyprstack-session";
    };

    systemd.user.services.hyprstack-session = {
      description = "Hyprstack desktop session";
      # Pull in graphical-session.target and settle before it is reached: it
      # refuses a manual start, so nothing else raises it, and from 1.22 on
      # xdg-desktop-portal holds a Requisite= on it.
      partOf = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      before = [ "graphical-session.target" ];
      unitConfig.ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${package}/bin/hyprstack-session-runner";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = 10;
        KillMode = "process";
      };
    };

    systemd.user.services.hyprstack-vpn = {
      description = "Hyprstack VPN core";
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${package}/bin/hyprstack-vpn serve";
        Restart = "on-failure";
        RestartSec = 3;
        UMask = "0077";
      };
    };
  };
}
