moduleConfig: {
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.vscode-server = let
    inherit (lib) mkEnableOption mkOption;
    inherit (lib.types) lines listOf nullOr package str bool passwdEntry;
  in {
    enable = mkEnableOption "VS Code Server autofix";

    enableFHS = mkEnableOption "a FHS compatible environment";

    nodejsPackage = mkOption {
      type = nullOr package;
      default = null;
      example = pkgs.nodejs_20;
      description = ''
        Whether to use a specific Node.js rather than the version supplied by VS Code server.
      '';
    };

    extraRuntimeDependencies = mkOption {
      type = listOf package;
      default = [ ];
      description = ''
        A list of extra packages to use as runtime dependencies.
        It is used to determine the RPATH to automatically patch ELF binaries with,
        or when a FHS compatible environment has been enabled,
        to determine its extra target packages.
      '';
    };

    installPath = mkOption {
      type = str;
      default = "$HOME/.vscode-server";
      example = "$HOME/.vscode-server-oss";
      description = ''
        The install path.
      '';
    };

    postPatch = mkOption {
      type = lines;
      default = "";
      description = ''
        Lines of Bash that will be executed after the VS Code server installation has been patched.
        This can be used as a hook for custom further patching.
      '';
    };

    enableForUsers = {
      enable = mkOption {
        type = bool;
        default = false;
        example = true;
        description = ''
          Whether to enable the VS Code Server auto-fix service for each user.

          This only makes sense if auto-fix-vscode-server is installed as a NixOS module.

          This automatically sets up the service's symlinks for systemd in each users' home directory.

          By default this will set it up for all regular users, but that list can be overridden by setting `users`.
        '';
      };

      users = mkOption {
        type = listOf (passwdEntry str);
        default = builtins.attrNames (lib.attrsets.filterAttrs (username: userOptions: userOptions.isNormalUser) config.users.users);
        defaultText = "builtins.attrNames (lib.filterAttrs (_: userOptions: userOptions.isNormalUser) config.users.users)";
        example = [ "alice" "bob" ];
        description = ''
          List of users to enable the VS Code Server auto-fix service for.

          By default this will fallback to the list of "normal" users.
        '';
      };
    };
  };

  config = let
    inherit (lib) mkDefault mkIf mkMerge;
    cfg = config.services.vscode-server;
    auto-fix-vscode-server =
      pkgs.callPackage ../../pkgs/auto-fix-vscode-server.nix
      (removeAttrs cfg [ "enable" "enableForUsers" ]);
  in
    mkIf cfg.enable (mkMerge [
      {
        services.vscode-server.nodejsPackage = mkIf cfg.enableFHS (mkDefault pkgs.nodejs_20);
      }
      (moduleConfig {
        name = "auto-fix-vscode-server";
        description = "Automatically fix the VS Code server used by the remote SSH extension";
        serviceConfig = {
          # When a monitored directory is deleted, it will stop being monitored.
          # Even if it is later recreated it will not restart monitoring it.
          # Unfortunately the monitor does not kill itself when it stops monitoring,
          # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
          Restart = "always";
          RestartSec = 0;
          ExecStart = "${auto-fix-vscode-server}/bin/auto-fix-vscode-server";
        };
        inherit config cfg lib;
      })
    ]);
}
