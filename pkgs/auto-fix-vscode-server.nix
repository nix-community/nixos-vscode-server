{ lib, buildFHSUserEnv ? buildFHSEnv, buildFHSEnv ? buildFHSUserEnv
, writeShellApplication, coreutils, findutils, inotify-tools, patchelf
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
  ] ++ extraRuntimeDependencies;

  nodejs = nodejsPackage;
  nodejsFHS = buildFHSUserEnv {
    name = "node";
    targetPkgs = _: runtimeDependencies;
    extraBuildCommands = ''
      if [[ -d /usr/lib/wsl ]]; then
        # Recursively symlink the lib files necessary for WSL
        # to properly function under the FHS compatible environment.
        # The -s stands for symbolic link.
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
  };

  patchELFScript = writeShellApplication {
    name = "patchelf-vscode-server";
    runtimeInputs = [ coreutils findutils patchelf ];
    text = ''
      INTERP=$(< ${stdenv.cc}/nix-support/dynamic-linker)
      RPATH=${makeLibraryPath runtimeDependencies}
      bin_dir=$1

      # NOTE: We don't log here because it won't show up in the output of the user service.

      # Check if the installation is already full patched.
      if [[ ! -e $bin_dir/.patched ]] || (( $(< "$bin_dir/.patched") )); then
        exit 0
      fi

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

      # Mark the bin directory as being fully patched.
      echo 1 > "$bin_dir/.patched"
    '';
  };

  autoFixScript = writeShellApplication {
    name = "auto-fix-vscode-server";
    runtimeInputs = [ coreutils findutils inotify-tools ];
    text = ''
      bins_dir=${installPath}/bin

      patch_bin () {
        local bin=$1 actual_dir=$bins_dir/$1 bin_dir
        bin=''${bin:0:40}
        bin_dir=$bins_dir/$bin

        if [[ -e $actual_dir/.patched ]]; then
          return 0
        fi

        echo "Patching Node.js of VS Code server installation in $actual_dir..." >&2

        ${optionalString (nodejs != null) ''
          ln -sfT ${if enableFHS then nodejsFHS else nodejs}/bin/node "$actual_dir/node"
        ''}

        ${optionalString (!enableFHS) ''
          mv "$actual_dir/node" "$actual_dir/node.orig"
          cat <<EOF > "$actual_dir/node"
          #!/usr/bin/env sh

          # The core utilities are missing in the case of WSL, but required by Node.js.
          PATH="\''${PATH:+\''${PATH}:}${makeBinPath [ coreutils ]}"

          # We leave the rest up to the Bash script
          # to keep having to deal with 'sh' compatibility to a minimum.
          ${patchELFScript}/bin/patchelf-vscode-server '$bin_dir'

          # Let Node.js take over as if this script never existed.
          exec '$bin_dir/node.orig' "\$@"
          EOF
          chmod +x "$actual_dir/node"
        ''}

        # Mark the bin directory as being patched.
        echo 0 > "$bin_dir/.patched"
      }

      # Fix any existing symlinks before we enter the inotify loop.
      if [[ -e $bins_dir ]]; then
        while read -rd ''' bin; do
          patch_bin "$bin"
        done < <(find "$bins_dir" -mindepth 1 -maxdepth 1 -type d -printf '%P\0')
      else
        mkdir -p "$bins_dir"
      fi

      while IFS=: read -r bin event; do
        # A new version of the VS Code Server is being created.
        if [[ $event == 'CREATE,ISDIR' ]]; then
          actual_dir=$bins_dir/$bin
          echo "VS Code server is being installed in $actual_dir..." >&2
          touch "$actual_dir/node"
          inotifywait -qq -e DELETE_SELF "$actual_dir/node"
          patch_bin "$bin"
        # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
        elif [[ $event == DELETE_SELF ]]; then
          # See the comments above Restart in the service config.
          exit 0
        fi
      done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%f:%e' "$bins_dir")
    '';
  };

in autoFixScript
