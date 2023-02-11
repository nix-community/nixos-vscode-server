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
    
    if [[ ! -d "$bin_dir" ]]; then
      echo "Going back to sleep, this is not a directory."
      return
    fi

    echo "Patching $bin_dir/node"
    ln -sfT ${nodejsWrapped}/bin/node "$bin_dir/node"
    echo "Done patching node."

    echo "Checking for helper binaries..."
    local iter=0
    while [[ ! -e "$bin_dir/node_modules/node-pty/build/Release/spawn-helper" && $iter -lt 50 ]]; do
      (( iter++ ))
      echo "Waiting for helper binaries to be populated... attempt $iter of 50"
      sleep 0.1
    done

    if [[ $iter -ge 50 ]]; then
      echo "Timed out waiting for helper binaries after 5s!"
    else
      echo "Found helper binaries."
    fi

    echo "Attempting patches within $bin_dir"
    while read -rd ''' bin; do
      if ! interp=$(patchelf --print-interpreter "$bin" 2>/dev/null); then
        # skip, not patchable (statically linked or non-ELF)
        continue
      fi
      if [[ "$interp" == "$node_interp" ]]; then
        echo "Skipping $bin as it's already patched"
        continue
      fi
      echo "Patching $bin..."
      patchelf --set-interpreter "$node_interp" --set-rpath "$node_rpath" "$bin"
      patchelf --shrink-rpath "$bin"
    done < <(find "$bin_dir" -type f -perm -100 -printf '%p\0')
  }

  # Fix any existing symlinks before we enter the inotify loop.
  if [[ -e $bins_dir ]]; then
    while read -rd ''' bin_dir; do
      patch_bin "$bin_dir"
    done < <(find "$bins_dir" -type d -mindepth 1 -maxdepth 1 -printf '%p\0')
  else
    mkdir -p "$bins_dir"
  fi

  while IFS=: read -r bin_dir event; do
    if [[ $event == 'CREATE,ISDIR' ]]; then
      echo "VSCode Server is being created at $bin_dir"
      # Create a trigger to know when their node is being created and replace it for our symlink.
      touch "$bin_dir/node"
      inotifywait -qq -e DELETE_SELF "$bin_dir/node"
      echo "VSCode Server nodejs binary is ready for patching"
      patch_bin "$bin_dir"
    # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
    elif [[ $event == DELETE_SELF ]]; then
      # See the comments above Restart in the service config.
      exit 0
    fi
  done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bins_dir")
''
