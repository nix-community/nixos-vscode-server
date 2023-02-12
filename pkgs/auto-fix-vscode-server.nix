{ lib, writeShellScript, coreutils, findutils, inotify-tools, patchelf, nodejs-16_x, buildFHSUserEnv
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

    extraBuildCommands = ''
      if [[ -d /usr/lib/wsl ]]
      then
        cp -rsHf /usr/lib/wsl usr/lib/wsl
      fi
    '';

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
  node_interp=$(patchelf --print-interpreter ${nodejs}/bin/node)
  node_rpath=$(patchelf --print-rpath ${nodejs}/bin/node)

  patch_bin() {
    local bin_dir=$1 interp
    ln -sfT ${nodejsWrapped}/bin/node "$bin_dir/node"
    while read -rd ''' bin; do
      # Check if binary is patchable, e.g. not a statically-linked or non-ELF binary.
      if ! interp=$(patchelf --print-interpreter "$bin" 2>/dev/null); then
        continue
      fi
      # Check if it is not already patched for Nix.
      if [[ $interp == "$node_interp" ]]; then
        continue
      fi
      patchelf --set-interpreter "$node_interp" --set-rpath "$node_rpath" "$bin"
      patchelf --shrink-rpath "$bin"
    done < <(find "$bin_dir" -type f -perm -100 -printf '%p\0')
  }

  # Fix any existing symlinks before we enter the inotify loop.
  if [[ -e $bins_dir ]]; then
    while read -rd ''' bin_dir; do
      patch_bin "$bin_dir"
    done < <(find "$bins_dir" -mindepth 1 -maxdepth 1 -printf '%p\0')
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
