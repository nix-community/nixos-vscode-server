{ lib, writeShellScript, coreutils, findutils, inotify-tools, ripgrep, buildFHSUserEnv, nodejs-16_x
, nodejsPackage ? nodejs-16_x
, extraFHSPackages ? (pkgs: [ ])
, installPath ? "~/.vscode-server"
}:

let
  # Based on: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/editors/vscode/generic.nix
  nodejs = buildFHSUserEnv {
    name = "node";

    # additional libraries which are commonly needed for extensions
    targetPkgs = pkgs: (builtins.attrValues {
      inherit (pkgs)
        # ld-linux-x86-64-linux.so.2 and others
        glibc

        # dotnet
        curl
        icu
        libunwind
        libuuid
        lttng-ust
        openssl
        zlib

        # mono
        krb5
      ;
    }) ++ extraFHSPackages pkgs;

    extraBuildCommands = ''
      cp -rsHf /usr/lib/wsl "usr/lib/wsl"
    '';

    runScript = "${nodejsPackage}/bin/node";

    meta = {
      description = ''
        Wrapped variant of Node.js which launches in an FHS compatible envrionment,
        which should allow for easy usage of extensions without nix-specific modifications.
      '';
    };
  };

in writeShellScript "auto-fix-vscode-server.sh" ''
  set -euo pipefail
  PATH=${lib.makeBinPath [ coreutils findutils inotify-tools ]}
  bin_dir=${installPath}/bin

  # Fix any existing symlinks before we enter the inotify loop.
  if [[ -e $bin_dir ]]; then
    find "$bin_dir" -mindepth 2 -maxdepth 2 -name node -exec ln -sfT ${nodejs}/bin/node {} \;
    find "$bin_dir" -path '*/@vscode/ripgrep/bin/rg' -exec ln -sfT ${ripgrep}/bin/rg {} \;
  else
    mkdir -p "$bin_dir"
  fi

  while IFS=: read -r bin_dir event; do
    # A new version of the VS Code Server is being created.
    if [[ $event == 'CREATE,ISDIR' ]]; then
      # Create a trigger to know when their node is being created and replace it for our symlink.
      touch "$bin_dir/node"
      inotifywait -qq -e DELETE_SELF "$bin_dir/node"
      ln -sfT ${nodejs}/bin/node "$bin_dir/node"
      ln -sfT ${ripgrep}/bin/rg "$bin_dir/node_modules/@vscode/ripgrep/bin/rg"
    # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
    elif [[ $event == DELETE_SELF ]]; then
      # See the comments above Restart in the service config.
      exit 0
    fi
  done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bin_dir")
''
