{
  lib,
  buildFHSEnv,
  runtimeShell,
  writeShellScript,
  writeShellApplication,
  coreutils,
  findutils,
  inotify-tools,
  patchelf,
  stdenv,
  curl,
  icu,
  libunwind,
  libuuid,
  lttng-ust,
  openssl,
  zlib,
  krb5,
  enableFHS ? false,
  nodejsPackage ? null,
  extraRuntimeDependencies ? [ ],
  installPath ? [ "$HOME/.vscode-server" ],
  postPatch ? "",
}: let
  inherit (lib) makeBinPath makeLibraryPath optionalString;

  # Based on: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/editors/vscode/generic.nix
  runtimeDependencies =
    [
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
    ]
    ++ extraRuntimeDependencies;

  nodejs = nodejsPackage;
  nodejsFHS = buildFHSEnv {
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
      bin_dir="$1"
      patched_file="$bin_dir/.nixos-patched"

      # NOTE: We don't log here because it won't show up in the output of the user service.

      # Check if the installation is already full patched.
      if [[ ! -e $patched_file ]] || (( $(< "$patched_file") )); then
        exit 0
      fi

      ${optionalString (!enableFHS) ''
        INTERP=$(< ${stdenv.cc}/nix-support/dynamic-linker)
        RPATH=${makeLibraryPath runtimeDependencies}

        patch_elf () {
          local elf=$1 interp

          # Check if binary is patchable, e.g. not a statically-linked or non-ELF binary.
          if ! interp=$(patchelf --print-interpreter "$elf" 2>/dev/null); then
            return
          fi

          # Check if it is not already patched for Nix.
          if [[ $interp == "$INTERP" ]]; then
            return
          fi

          # Patch the binary based on the binary of Node.js,
          # which should include all dependencies they might need.
          patchelf --set-interpreter "$INTERP" --set-rpath "$RPATH" "$elf"

          # The actual dependencies are probably less than that of Node.js,
          # so shrink the RPATH to only keep those that are actually needed.
          patchelf --shrink-rpath "$elf"
        }

        while read -rd ''' elf; do
          patch_elf "$elf"
        done < <(find "$bin_dir" -type f -perm -100 -printf '%p\0')
      ''}

      # Mark the bin directory as being fully patched.
      echo 1 > "$patched_file"

      ${optionalString (postPatch != "") ''${writeShellScript "post-patchelf-vscode-server" postPatch} "$bin"''}
    '';
  };

  autoFixScript = writeShellApplication {
    name = "auto-fix-vscode-server";
    runtimeInputs = [ coreutils findutils inotify-tools ];
    text = ''
      # Convert installPath list to an array
      IFS=':' read -r -a installPaths <<< "${lib.concatStringsSep ":" installPath}"

      patch_bin () {
        local actual_dir="$1"
        local current_install_path="$2"
        local patched_file="$actual_dir/.nixos-patched"

        if [[ -e $patched_file ]]; then
          return 0
        fi

        # Backwards compatibility with previous versions of nixos-vscode-server.
        local old_patched_file
        old_patched_file="$(basename "$actual_dir")"
        if [[ $old_patched_file == "server" ]]; then
          old_patched_file="$(basename "$(dirname "$actual_dir")")"
          old_patched_file="$current_install_path/.''${old_patched_file%%.*}.patched"
        else
          old_patched_file="$current_install_path/.''${old_patched_file%%-*}.patched"
        fi
        if [[ -e $old_patched_file ]]; then
          echo "Migrating old nixos-vscode-server patch marker file to new location in $actual_dir." >&2
          cp "$old_patched_file" "$patched_file"
          return 0
        fi

        echo "Patching Node.js of VS Code server installation in $actual_dir..." >&2

        mv "$actual_dir/node" "$actual_dir/node.patched"

        ${optionalString (enableFHS) ''
        ln -sfT ${nodejsFHS}/bin/node "$actual_dir/node"
      ''}

        ${optionalString (!enableFHS || postPatch != "") ''
        cat <<EOF > "$actual_dir/node"
        #!${runtimeShell}

        # The core utilities are missing in the case of WSL, but required by Node.js.
        PATH="\''${PATH:+\''${PATH}:}${makeBinPath [ coreutils ]}"

        # We leave the rest up to the Bash script
        # to keep having to deal with 'sh' compatibility to a minimum.
        ${patchELFScript}/bin/patchelf-vscode-server \$(dirname "\$0")

        # Let Node.js take over as if this script never existed.
        ${
          let nodePath = (if (nodejs != null)
          then "${if enableFHS then nodejsFHS else nodejs}/bin/node"
          else ''\$(dirname "\$0")/node.patched'');
          in ''exec "${nodePath}" "\$@"''
        }
        EOF
        chmod +x "$actual_dir/node"
      ''}

        # Mark the bin directory as being patched.
        echo 0 > "$patched_file"
      }

      # Initialize arrays for bins_dirs_1 and bins_dirs_2
      bins_dirs_1=()
      bins_dirs_2=()

      # Populate bins_dirs_1 and bins_dirs_2 based on installPaths
      for current_install_path in "''${installPaths[@]}"; do
        bins_dirs_1+=("$current_install_path/bin")
        bins_dirs_2+=("$current_install_path/cli/servers")
      done

      # Create directories and patch existing bins
      for bins_dir_1 in "''${bins_dirs_1[@]}"; do
        mkdir -p "$bins_dir_1"
        while read -rd ''' bin; do
          patch_bin "$bin" "$(dirname "$(dirname "$bin")")"
        done < <(find "$bins_dir_1" -mindepth 1 -maxdepth 1 -type d -printf '%p\0')
      done
      for bins_dir_2 in "''${bins_dirs_2[@]}"; do
        mkdir -p "$bins_dir_2"
        while read -rd ''' bin; do
          bin="$bin/server"
          patch_bin "$bin" "$(dirname "$(dirname "$bin")")"
        done < <(find "$bins_dir_2" -mindepth 1 -maxdepth 1 -type d -printf '%p\0')
      done

      # Watch for new installations
      while IFS=: read -r bins_dir bin event; do
        # A new version of the VS Code Server is being created.
        if [[ $event == 'CREATE,ISDIR' ]]; then
          actual_dir="$bins_dir$bin"
          actual_install_path="$(dirname "$bins_dir")"
          if [[ "$bins_dir" == */cli/servers/ ]]; then
            actual_dir="$actual_dir/server"
            # Hope that VSCode will not die if the directory exists when it tries to install, otherwise we'll need to
            # use a coproc to wait for the directory to be created without entering in a race, then watch for the node
            # file to be created (probably while also avoiding a race)
            # https://unix.stackexchange.com/a/185370
            mkdir -p "$actual_dir"
            actual_install_path="$(dirname "$(dirname "$bins_dir")")"
          fi
          echo "VS Code server is being installed in $actual_dir..." >&2
          # Quickly create a node file, which will be removed when vscode installs its own version
          touch "$actual_dir/node"
          # Hope we don't race...
          inotifywait -qq -e DELETE_SELF "$actual_dir/node"
          patch_bin "$actual_dir" "$actual_install_path"
        # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
        elif [[ $event == DELETE_SELF ]]; then
          # See the comments above Restart in the service config.
          exit 0
        fi
      done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w:%f:%e' "''${bins_dirs_1[@]}" "''${bins_dirs_2[@]}")
    '';
  };
in
autoFixScript
