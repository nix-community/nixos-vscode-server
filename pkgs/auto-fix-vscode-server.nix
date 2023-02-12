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

  patchScript = writeShellScript "patch-vscode-server.sh" ''
    set -euo pipefail
    PATH=${lib.makeBinPath [ coreutils findutils patchelf ]}
    bin_dir=$1

    echo "Patching VS Code server installation in $bin_dir..." >&2

    node_interp=$(patchelf --print-interpreter ${nodejs}/bin/node)
    node_rpath=$(patchelf --print-rpath ${nodejs}/bin/node)
    while read -rd ''' bin; do
      # Check if binary is patchable, e.g. not a statically-linked or non-ELF binary.
      if ! interp=$(patchelf --print-interpreter "$bin" 2>/dev/null); then
        continue
      fi

      # Check if it is not already patched for Nix.
      if [[ $interp == "$node_interp" ]]; then
        continue
      fi

      # Patch the binary based on the binary of Node.js,
      # which should include all dependencies they might need.
      patchelf --set-interpreter "$node_interp" --set-rpath "$node_rpath" "$bin"

      # The actual dependencies are probably less than that of Node.js,
      # so shrink the RPATH to only keep those that are actually needed.
      patchelf --shrink-rpath "$bin"

      echo "Patched $bin." >&2
    done < <(find "$bin_dir" -type f -perm -100 -printf '%p\0')

    touch "$bin_dir/.patched"
  '';

in writeShellScript "auto-fix-vscode-server.sh" ''
  set -euo pipefail
  PATH=${lib.makeBinPath [ coreutils findutils inotify-tools ]}
  bins_dir=${installPath}/bin

  patch_bin_dir () {
    local bin_dir=$1

    if [[ -e $bin_dir/node.orig ]]; then
      return 0
    fi

    mv "$bin_dir/node" "$bin_dir/node.orig"
    cat <<EOF > "$bin_dir/node"
#!/usr/bin/env bash

# Patch the VS Code server installation only if it is not already patched.
if [[ ! -e '$bin_dir/.patched' ]]; then
  ${patchScript} '$bin_dir'
fi

exec '$bin_dir/node.orig' "\$@"
EOF
    chmod +x "$bin_dir/node"
  }

  # Fix any existing symlinks before we enter the inotify loop.
  if [[ -e $bins_dir ]]; then
    while read -rd ''' bin_dir; do
      patch_bin_dir "$bin_dir"
    done < <(find "$bins_dir" -mindepth 1 -maxdepth 1 -type d -printf '%p\0')
  else
    mkdir -p "$bins_dir"
  fi

  while IFS=: read -r bin_dir event; do
    # A new version of the VS Code Server is being created.
    if [[ $event == 'CREATE,ISDIR' ]]; then
      echo "VS Code server is being installed in $bin_dir..."
      touch "$bin_dir/node"
      inotifywait -qq -e DELETE_SELF "$bin_dir/node"
      patch_bin_dir "$bin_dir"
    # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
    elif [[ $event == DELETE_SELF ]]; then
      # See the comments above Restart in the service config.
      exit 0
    fi
  done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bins_dir")
''
