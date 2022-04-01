moduleConfig:
{ lib, pkgs, ... }:

with lib;

{
  options.services.vscode-server.enable = with types; mkEnableOption "VS Code Server";

  config = moduleConfig rec {
    name = "auto-fix-vscode-server";
    description = "Automatically fix the VS Code server used by the remote SSH extension";
    serviceConfig = {
      # When a monitored directory is deleted, it will stop being monitored.
      # Even if it is later recreated it will not restart monitoring it.
      # Unfortunately the monitor does not kill itself when it stops monitoring,
      # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
      Restart = "always";
      RestartSec = 0;
      ExecStart = "${pkgs.writeShellScript "${name}.sh" ''
        set -euo pipefail
        PATH=${makeBinPath (with pkgs; [ coreutils findutils inotify-tools ])}
        bin_dir=~/.vscode-server/bin

        # Fix any existing symlinks before we enter the inotify loop.
        if [[ -e $bin_dir ]]; then
          find "$bin_dir" -mindepth 2 -maxdepth 2 -name node -exec ln -sfT ${pkgs.nodejs-16_x}/bin/node {} \;
          find "$bin_dir" -path '*/@vscode/ripgrep/bin/rg' -exec ln -sfT ${pkgs.ripgrep}/bin/rg {} \;
        else
          mkdir -p "$bin_dir"
        fi

        while IFS=: read -r bin_dir event; do
          # A new version of the VS Code Server is being created.
          if [[ $event == 'CREATE,ISDIR' ]]; then
            # Create a trigger to know when their node is being created and replace it for our symlink.
            touch "$bin_dir/node"
            inotifywait -qq -e DELETE_SELF "$bin_dir/node"
            ln -sfT ${pkgs.nodejs-16_x}/bin/node "$bin_dir/node"
            ln -sfT ${pkgs.ripgrep}/bin/rg "$bin_dir/node_modules/@vscode/ripgrep/bin/rg"
          # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
          elif [[ $event == DELETE_SELF ]]; then
            # See the comments above Restart in the service config.
            exit 0
          fi
        done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bin_dir")
      ''}";
    };
  };
}
