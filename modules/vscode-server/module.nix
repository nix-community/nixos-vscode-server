moduleConfig: {
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.vscode-server = let
    inherit (lib) mkEnableOption mkOption;
    inherit (lib.types) lines listOf nullOr package str;
  in {
    enable = mkEnableOption "VS Code Server";

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
      type = lib.types.coercedTo str (x: [x]) (listOf str);
      default = [ "$HOME/.vscode-server" ];
      example = [ "$HOME/.vscode-server" "$HOME/.vscode-server-oss" "$HOME/.vscode-server-insiders" ];
      description = ''
        Path(s) where VS Code Server will be installed.
        Accepts either a single path string or a list of paths.
        String values are automatically coerced to a single-element list for backwards compatibility.
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
  };

  config = let
    inherit (lib) mkDefault mkIf mkMerge;
    cfg = config.services.vscode-server;
    auto-fix-vscode-server =
      pkgs.callPackage ../../pkgs/auto-fix-vscode-server.nix
      (removeAttrs cfg [ "enable" ]);
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
          RestartSec = 5;
          ExecStart = "${auto-fix-vscode-server}/bin/auto-fix-vscode-server";
        };
      })
    ]);
}
