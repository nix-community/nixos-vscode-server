{ lib, writeShellScript, coreutils, findutils, inotify-tools, patchelf, ripgrep, nodejs-16_x, buildFHSUserEnv
, nodejsPackage ? nodejs-16_x
, enableFHS ? false
, extraFHSPackages ? (pkgs: [ ])
, installPath ? "~/.vscode-server"
}:

let
  nodejs = nodejsPackage;

  # Based on: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/editors/vscode/generic.nix
  nodejsFHS = buildFHSUserEnv {
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

    runScript = "${nodejs}/bin/node";

    meta = {
      description = ''
        Wrapped variant of Node.js which launches in an FHS compatible envrionment,
        which should allow for easy usage of extensions without nix-specific modifications.
      '';
    };
  };

  nodejsWrapped = if enableFHS then nodejsFHS else nodejs;

in writeShellScript "auto-fix-vscode-server.sh" ''
  set -euo pipefail
  PATH=${lib.makeBinPath [ coreutils findutils inotify-tools patchelf ]}
  bins_dir=${installPath}/bin

  patch_bin() {
    bin_dir=$1
    ln -sfT ${nodejsWrapped}/bin/node "$bin_dir/node"
    if [[ -e $bin_dir/node_modules/node-pty/build/Release/spawn-helper ]]; then
      patchelf \
        --set-interpreter "$(patchelf --print-interpreter ${nodejs}/bin/node)" \
        --add-rpath "$(patchelf --print-rpath ${nodejs}/bin/node)" \
        $bin_dir/node_modules/node-pty/build/Release/spawn-helper
    fi
    ln -sfT ${ripgrep}/bin/rg "$bin_dir/node_modules/@vscode/ripgrep/bin/rg"
  }

  # Fix any existing symlinks before we enter the inotify loop.
  if [[ -e $bins_dir ]]; then
    while read -rd ''' bin_dir; do
      patch_bin "$bin_dir"
    done < <(find "$bins_dir" -mindepth 1 -maxdepth 1 -printf '%P\0')
  else
    mkdir -p "$bins_dir"
  fi

  while IFS=: read -r bin_dir event; do
    # A new version of the VS Code Server is being created.
    if [[ $event == 'CREATE,ISDIR' ]]; then
      # Create a trigger to know when their node is being created and replace it for our symlink.
      touch "$bin_dir/node"
      inotifywait -qq -e DELETE_SELF "$bin_dir/node"
      patch_bin "$bin_dir"
    # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
    elif [[ $event == DELETE_SELF ]]; then
      # See the comments above Restart in the service config.
      exit 0
    fi
  done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bins_dir")
''
