self: { config, lib, pkgs, ... }:
let
  cfg = config.programs.hyprstack;
  package = cfg.package;
in {
  options.programs.hyprstack = {
    enable = lib.mkEnableOption "Hyprstack user configuration";
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional Hyprland Lua configuration applied after Hyprstack and local overrides.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "Hyprstack package matching the system Hyprland package.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];
    home.sessionVariables = {
      HYPRSTACK_DATA_DIR = "${package}/share/hyprstack";
      HYPRSTACK_SESSION_COMMAND = "${package}/bin/hyprstack-session";
    };
    xdg.configFile."hypr" = {
      source = "${package}/share/hyprstack/shell/assets/hyprland/config";
      recursive = true;
    };
    # The compositor can start without sourcing hm-session-vars.sh (for example
    # from a display manager). Resolve its runtime from this generation directly.
    xdg.configFile."hyprstack/hypr-user.lua".text = ''
      hl.env("HYPRSTACK_DATA_DIR", "${package}/share/hyprstack")
      hl.env("HYPRSTACK_SESSION_COMMAND", "${package}/bin/hyprstack-session")
      dofile("${package}/share/hyprstack/defaults/hyprstack/hypr-user.lua")
      ${cfg.extraConfig}
    '';

    systemd.user.services.hyprstack-session = {
      Unit = {
        Description = "Hyprstack desktop session";
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        Type = "simple";
        ExecStart = "${package}/bin/hyprstack-session-runner";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = 10;
        KillMode = "process";
      };
    };

    systemd.user.services.hyprstack-vpn = {
      Unit = {
        Description = "Hyprstack VPN core";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${package}/bin/hyprstack-vpn serve";
        Restart = "on-failure";
        RestartSec = 3;
        UMask = "0077";
      };
    };

    # GUI-editable preferences stay ordinary user files. Only missing defaults
    # are created, so activation preserves monitor rules and local overrides.
    home.activation.hyprstackDefaults = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.python3}/bin/python3 - ${lib.escapeShellArg config.xdg.configHome} ${package} <<'PY'
      from pathlib import Path
      import shutil, sys
      config, package = map(Path, sys.argv[1:])
      target = config / "hyprstack"
      target.mkdir(parents=True, exist_ok=True)
      for source in (package / "share/hyprstack/defaults/hyprstack").iterdir():
          destination = target / source.name
          if not destination.exists() and not destination.is_symlink():
              shutil.copyfile(source, destination)
      PY
    '';
  };
}
