# Evaluate with: nix-instantiate --eval --strict --json distribution/tests/test_nixos_module.nix
#   --arg nixpkgsPath /path/to/pinned/nixpkgs
# No package build or running system configuration is required.
{
  nixpkgsPath,
  modulePath ? ../../nix/nixos-module.nix,
  packageOptions ? { },
  sessionOptions ? { },
  conflictingPackage ? false,
}:
let
  pkgs = import nixpkgsPath { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  compositor = pkgs.hyprland.override packageOptions;
  shell = pkgs.runCommand "hyprstack-module-test" {
    passthru = {
      hyprland = compositor;
      inherit (pkgs) quickshell;
    };
  } "mkdir -p $out";
  self.packages.x86_64-linux.default = shell;
  system = import (nixpkgsPath + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      (import modulePath self)
      {
        boot.isContainer = true;
        system.stateVersion = "26.05";
        programs.hyprstack.enable = true;
        programs.hyprland = sessionOptions // lib.optionalAttrs conflictingPackage {
          package = lib.mkForce (pkgs.hyprland.override {
            enableXWayland = false;
            withUWSM = false;
          });
        };
      }
    ];
  };
  cfg = system.config;
  result = {
    compilerPackage = toString compositor;
    sessionPackage = toString cfg.programs.hyprland.package;
    sameCompositor = toString compositor == toString cfg.programs.hyprland.package;
    failedAssertions = map (assertion: assertion.message)
      (lib.filter (assertion: !assertion.assertion) cfg.assertions);
    fileChooserBackends = cfg.xdg.portal.config.hyprland."org.freedesktop.impl.portal.FileChooser";
    pamLockAvailable = builtins.hasAttr "hyprlock" cfg.security.pam.services;
  };
in
assert lib.assertMsg (result.sameCompositor != conflictingPackage) "Compositor selection regression";
assert lib.assertMsg ((result.failedAssertions != [ ]) == conflictingPackage) "NixOS assertion regression";
assert result.fileChooserBackends == "hyprstack;gtk" && result.pamLockAvailable;
result
