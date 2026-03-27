{
  description = "NixOS VSCode server";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # The package depends on `inotify-tools` which is only available on Linux.
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      flake = {
        nixosModule = self.nixosModules.default; # Deprecrated, but perhaps still in use.
        nixosModules.default = import ./modules/vscode-server;
        nixosModules.home = self.homeModules.default; # Backwards compatiblity.
        homeModules.default = import ./modules/vscode-server/home.nix; # Consistent with homeConfigurations.
      };

      perSystem =
        { pkgs, ... }:
        let
          auto-fix-vscode-server = pkgs.callPackage ./pkgs/auto-fix-vscode-server.nix { };
        in
        {
          packages = {
            inherit auto-fix-vscode-server;
            default = auto-fix-vscode-server;
          };
          checks = {
            inherit auto-fix-vscode-server;
          };
        };
    };
}
