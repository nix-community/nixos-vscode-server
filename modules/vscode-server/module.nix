moduleConfig:
{ config, lib, pkgs, ... }:

{
  options.services.vscode-server = let
    inherit (lib) mkEnableOption mkOption;
    inherit (lib.types) bool listOf package str unspecified;
  in {
    enable = mkEnableOption "VS Code Server";

    enableFHS = mkOption {
      type = bool;
      default = true;
      example = false;
      description = ''
        Whether to enable FHS compatible environment.
      '';
    };

    extraFHSPackages = mkOption {
      type = unspecified;
      default = pkgs: [ ];
      description = ''
        A function to add extra packages to the FHS compatible environment.
      '';
    };

    nodejsPackage = mkOption {
      type = package;
      default = pkgs.nodejs-16_x;
      example = pkgs.nodejs-18_x;
      description = ''
        The Node.js package of the Node.js version used by VS Code version of the client.
      '';
    };

    installPath = mkOption {
      type = str;
      default = "~/.vscode-server";
      example = "~/.vscode-server-oss";
      description = ''
        The install path.
      '';
    };
  };

  config = let cfg = config.services.vscode-server; in lib.mkIf cfg.enable (moduleConfig {
    name = "auto-fix-vscode-server";
    description = "Automatically fix the VS Code server used by the remote SSH extension";
    serviceConfig = {
      # When a monitored directory is deleted, it will stop being monitored.
      # Even if it is later recreated it will not restart monitoring it.
      # Unfortunately the monitor does not kill itself when it stops monitoring,
      # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
      Restart = "always";
      RestartSec = 0;
      ExecStart = pkgs.callPackage ../../pkgs/auto-fix-vscode-server.nix (removeAttrs cfg [ "enable" ]);
    };
  });
}
