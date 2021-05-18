moduleConfig:
{ lib, pkgs, config, ... }:

with lib;

{
  options.services.auto-fix-vscode-server = with types;{
    enable = mkEnableOption "auto-fix service for vscode-server in NixOS";
    nodePackage = mkOption {
      type = package;
      default = pkgs.nodejs-14_x;
    };
  };

  config =
    let
      cfg = config.services.auto-fix-vscode-server;
      nodePath = "${cfg.nodePackage}/bin/node";
      mkStartScript = name: pkgs.writeShellScript "${name}.sh" ''
        set -euo pipefail
        PATH=${makeBinPath (with pkgs; [ coreutils inotify-tools ])}
        bin_dir=~/.vscode-server/bin
        [[ -e $bin_dir ]] &&
        find "$bin_dir" -mindepth 2 -maxdepth 2 -name node -type f -exec ln -sfT ${nodePath} {} \; ||
        mkdir -p "$bin_dir"

        while IFS=: read -r bin_dir event; do
          # A new version of the VS Code Server is being created.
          if [[ $event == 'CREATE,ISDIR' ]]; then
            # Create a trigger to know when their node is being created and replace it for our symlink.
            touch "$bin_dir/node"
            inotifywait -qq -e DELETE_SELF "$bin_dir/node"
            ln -sfT ${nodePath} "$bin_dir/node"
          # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
          elif [[ $event == DELETE_SELF ]]; then
            # See the comments above Restart in the service config.
            exit 0
          fi
        done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bin_dir")
      '';
    in
      mkIf cfg.enable (
        moduleConfig rec {
          name = "auto-fix-vscode-server";
          description = "Automatically fix the VS Code server used by the remote SSH extension";
          serviceConfig = {
            # When a monitored directory is deleted, it will stop being monitored.
            # Even if it is later recreated it will not restart monitoring it.
            # Unfortunately the monitor does not kill itself when it stops monitoring,
            # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
            Restart = "always";
            RestartSec = 0;
            ExecStart = "${mkStartScript name}";
          };
        }
      );
}
