# Visual Studio Code Server support in NixOS

Experimental support for VS Code Server in NixOS. The NodeJS by default supplied by VS Code cannot be used within NixOS due to missing hardcoded paths, so it is automatically replaced by a symlink to a compatible version of NodeJS that does work under NixOS.

## Installation

### NixOS module

You can add the module to your system in various ways. After the installation
you'll have to manually enable the service for each user (see below).

#### Install as a tarball

```nix
{
  imports = [
    (fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master")
  ];

  services.vscode-server.enable = true;
}
```

#### Install as a flake

```nix
{
  inputs.vscode-server.url = "github:msteen/nixos-vscode-server";

  outputs = { self, nixpkgs, vscode-server }: {
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      modules = [
        vscode-server.nixosModule
        ({ config, pkgs, ... }: {
          services.vscode-server.enable = true;
        })
      ];
    };
  };
}
```

#### Enable the service

And then enable them for the relevant users:

```bash
systemctl --user enable auto-fix-vscode-server.service
```

You will see the following message:

```
The unit files have no installation config (WantedBy=, RequiredBy=, Also=,
Alias= settings in the [Install] section, and DefaultInstance= for template
units). This means they are not meant to be enabled using systemctl.

Possible reasons for having this kind of units are:
• A unit may be statically enabled by being symlinked from another unit's
  .wants/ or .requires/ directory.
• A unit's purpose may be to act as a helper for some other unit which has
  a requirement dependency on it.
• A unit may be started when needed via activation (socket, path, timer,
  D-Bus, udev, scripted systemctl call, ...).
• In case of template units, the unit is meant to be enabled with some
  instance name specified.
```

However you can safely ignore it. The service will start automatically after reboot once enabled, or you can just start it immediately yourself with:

```
systemctl --user start auto-fix-vscode-server.service
```

### Home Manager

Put this code into your [home-manager](https://github.com/nix-community/home-manager) configuration i.e. in `~/.config/nixpkgs/home.nix`:

```nix
{
  imports = [
    "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
  ];

  services.vscode-server.enable = true;
}
```

## Usage

When using VS Code as released by Microsoft without any special needs, just enabling and starting the service should be enough to make things work. If you have some custom build or needs, there are a few options available that might help you out.

### `nodejsPackage`
The Node.js version needed for VS Code server is based on the VS Code version of the client. By default it should contain the version of Node.js needed by the latest version of VS Code. Considering this can change in the future and people might have different versions of VS Code running, it has been made configurable.

Disclaimer: I am not a very active user of this extension and even NixOS (at the moment), yet I know how important this extension can be to some people, so at least this way you can workaround it until the default get updated.

```nix
{
  services.vscode-server.nodejsPackage = pkgs.nodejs-18_x;
}
```

### `enableFHS`
A FHS compatible environment can be enabled to make binaries supplied by extensions work in NixOS without having to patch them. Note that this does come with downsides too, such as problematic support for SUID wrappers, which is why it is not enabled by default.

```nix
{
  services.vscode-server.enableFHS = true;
}
```

### `extraFHSPackages`
If you have an extensions that require a FHS compatible environment, but their binaries require dependencies that are not already included, you can add them here to make them available to the FHS environment.

```nix
{
  services.vscode-server.extraFHSPackages = pkgs: builtins.attrValues {
    inherit (pkgs) curl;
  };
}
```

### `installPath`
The installation path for VS Code server is configurable and the default can differ for alternative builds (e.g. oss and insider), so this option allows you to configure which installation path should be monitered and automatically fixed.

```nix
{
  services.vscode-server.installPath = "~/.vscode-server-oss";
}
```

## Troubleshooting

This is not really an issue with this project per se, but with systemd user services in NixOS in general. After updating it can be necessary to first disable the service again:

```bash
systemctl --user disable auto-fix-vscode-server.service
```

This will remove the symlink to the old version. Then you can enable/start it again.

### Connecting with SSH timed out

If the remote SSH session fails to start with this error:

> Failed to connect to the remote extension host server (Error: Connecting with SSH timed out)

Try adding this to your VS Code settings json:
```json
    "remote.SSH.useLocalServer": false,
```

Tested on VS Code version 1.63.2, connecting to the NixOS remote from a MacOS host.
