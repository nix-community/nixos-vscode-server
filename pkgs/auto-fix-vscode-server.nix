{ lib, buildFHSUserEnv
, writeShellScript, coreutils, findutils, inotify-tools, patchelf
, stdenv, curl, icu, libunwind, libuuid, lttng-ust, openssl, zlib, krb5
, enableFHS ? false
, nodejsPackage ? null
, extraRuntimeDependencies ? [ ]
, installPath ? "~/.vscode-server"
}:

let
  inherit (lib) makeBinPath makeLibraryPath optionalString;

  # Based on: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/editors/vscode/generic.nix
  runtimeDependencies = [
    stdenv.cc.libc
    stdenv.cc.cc

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
  ];

  nodejs = nodejsPackage;
  nodejsFHS = buildFHSUserEnv ({
    name = "node";
    targetPkgs = _: runtimeDependencies;
    extraBuildCommands = ''
      if [[ -d /usr/lib/wsl ]]; then
        cp -rsHf /usr/lib/wsl usr/lib/wsl
      fi
    '';
    runScript = "${nodejs}/bin/node";
    meta = {
      description = ''
        Wrapped variant of Node.js which launches in an FHS compatible envrionment,
        which should allow for easy usage of extensions without Nix-specific modifications.
      '';
    };
  });
  nodejsWrapped = if enableFHS then nodejsFHS else nodejs;

  patchELFScript = writeShellScript "patchelf-vscode-server.sh" ''
    set -euo pipefail
    PATH=${makeBinPath [ coreutils findutils patchelf ]}
    INTERP=$(cat ${stdenv.cc}/nix-support/dynamic-linker)
    RPATH=${makeLibraryPath runtimeDependencies}
    bin_dir=$1

    # NOTE: We don't log here because it won't show up in the output of the user service.

    while read -rd ''' elf; do
      # Check if binary is patchable, e.g. not a statically-linked or non-ELF binary.
      if ! interp=$(patchelf --print-interpreter "$elf" 2>/dev/null); then
        continue
      fi

      # Check if it is not already patched for Nix.
      if [[ $interp == "$INTERP" ]]; then
        continue
      fi

      # Patch the binary based on the binary of Node.js,
      # which should include all dependencies they might need.
      patchelf --set-interpreter "$INTERP" --set-rpath "$RPATH" "$elf"

      # The actual dependencies are probably less than that of Node.js,
      # so shrink the RPATH to only keep those that are actually needed.
      patchelf --shrink-rpath "$elf"
    done < <(find "$bin_dir" -type f -perm -100 -printf '%p\0')

    # Mark the bin directory as being patched.
    echo 1 > "$bin_dir/.patched"
  '';

in writeShellScript "auto-fix-vscode-server.sh" ''
  set -euo pipefail
  PATH=${lib.makeBinPath [ coreutils findutils inotify-tools ]}
  bins_dir=${installPath}/bin

  patch_bin_dir () {
    local bin_dir=$1

    if [[ -e $bin_dir/.patched ]]; then
      return 0
    fi

    echo "Patching Node.js of VS Code server installation in $bin_dir..." >&2

    ${optionalString (nodejsWrapped != null) ''
      ln -sfT ${nodejsWrapped}/bin/node "$bin_dir/node"
    ''}

    ${optionalString (!enableFHS) ''
      mv "$bin_dir/node" "$bin_dir/node.orig"
      cat <<EOF > "$bin_dir/node"
      #!/usr/bin/env bash

      # Patch the VS Code server installation only if it is not already patched.
      if ! (( \$(< '$bin_dir/.patched') )); then
        ${patchELFScript} '$bin_dir'
      fi

      exec '$bin_dir/node.orig' "\$@"
      EOF
      chmod +x "$bin_dir/node"
    ''}

    echo 0 > "$bin_dir/.patched"
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
      echo "VS Code server is being installed in $bin_dir..." >&2
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
