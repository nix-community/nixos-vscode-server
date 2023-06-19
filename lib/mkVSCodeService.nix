moduleConfig: name: defaultConfig: {
  config,
  lib,
  pkgs,
  ...
}: {
  _file = __curPos.file;

  options.services."vscode-${name}" = let
    inherit (lib) types;
  in {
    enable = lib.mkEnableOption "VS Code ${name}";

    enableFHS = lib.mkEnableOption "a FHS compatible environment";

    nodejsPackage = lib.mkOption {
      type = types.nullOr types.package;
      default = null;
      example = pkgs.nodejs-16_x;
      description = ''
        Whether to use a specific Node.js rather than the version supplied by VS Code ${name}.
      '';
    };

    extraRuntimeDependencies = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        A list of extra packages to use as runtime dependencies.
        It is used to determine the RPATH to automatically patch ELF binaries with,
        or when a FHS compatible environment has been enabled,
        to determine its extra target packages.
      '';
    };

    installPath = lib.mkOption {
      type = types.str;
      example = "~/.vscode-server-oss";
      description = ''
        The install path.
      '';
    };

    postPatch = lib.mkOption {
      type = types.lines;
      default = "";
      description = ''
        Lines of Bash that will be executed after the VS Code ${name} installation has been patched.
        This can be used as a hook for custom further patching.
      '';
    };
  };

  config = let
    cfg = config.services."vscode-${name}";
    auto-fix-vscode-service =
      pkgs.callPackage ../../pkgs/auto-fix-vscode-service.nix
      ({ inherit name; } // removeAttrs cfg [ "enable" ]);
  in
    lib.mkIf cfg.enable (lib.mkMerge [
      { services."vscode-${name}".nodejsPackage = lib.mkIf cfg.enableFHS (lib.mkDefault pkgs.nodejs-16_x); }
      { services."vscode-${name}" = defaultConfig; }
      (moduleConfig {
        name = "auto-fix-vscode-${name}";
        description = "Automatically fix VS Code ${name}";
        serviceConfig = {
          # When a monitored directory is deleted, it will stop being monitored.
          # Even if it is later recreated it will not restart monitoring it.
          # Unfortunately the monitor does not kill itself when it stops monitoring,
          # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
          Restart = "always";
          RestartSec = 0;
          ExecStart = "${auto-fix-vscode-service}/bin/auto-fix-vscode-${name}";
        };
      })
    ]);
}
