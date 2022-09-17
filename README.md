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

```
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

When the service is enabled and running it should simply work, there is nothing for you to do.


#### Custom server path

A remote server location can be customized from the default `~/.vscode-server` in your `settings.json`, for example:

```jsonc
{
  // ...
  "remote.SSH.serverInstallPath": {
    "HOSTNAME": "/home/USER/.local/share",
  }
}
```

To reflect these changes in your configuration set the following option:

```nix
services.vscode-server.enable = true;
services.vscode-server.path = "~/.local/share/.vscode-server";
```

## Troubleshooting

This is not really an issue with this project per se, but with systemd user services in NixOS in general. After updating it can be necessary to first disable the service again:

```
systemctl --user disable auto-fix-vscode-server.service
````

This will remove the symlink to the old version. Then you can enable/start it again.

### Connecting with SSH timed out

If the remote SSH session fails to start with this error:

> Failed to connect to the remote extension host server (Error: Connecting with SSH timed out)

Try adding this to your VS Code settings json:
```
    "remote.SSH.useLocalServer": false,
```

Tested on VS Code version 1.63.2, connecting to the NixOS remote from a MacOS host.
