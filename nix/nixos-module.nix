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
    # nixpkgs overrides this package with the xwayland and UWSM options as
    # soon as it takes both arguments, which Hyprland 0.57 does, and builds a
    # Hyprland apart from the one the shell was built against. An override
    # that names no arguments keeps the package as it is.
    programs.hyprland.package = lib.mkDefault (package.hyprland // {
      override = args: package.hyprland.override args;
    });
    programs.hyprlock.enable = true;
    environment.systemPackages = [ package ];
    environment.sessionVariables = {
      HYPRSTACK_DATA_DIR = "${package}/share/hyprstack";
      HYPRSTACK_SESSION_COMMAND = "${package}/bin/hyprstack-session";
    };

    systemd.user.services.hyprstack-session = {
      description = "Hyprstack desktop session";
      partOf = [ "graphical-session.target" ];
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
