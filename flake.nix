{
  description = "NixOS VSCode server";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    {
      nixosModule = self.nixosModules.default; # Deprecrated, but perhaps still in use.
      nixosModules = let
        modules = import ./modules/nixos.nix;
      in
        modules
        // {
          default = modules.vscode-server;
          home = self.homeModules.default; # Backwards compatiblity.
        };
      # Consistent with homeConfigurations.
      homeModules.default = let
        modules = import ./modules/home.nix;
      in
        modules
        // {
          default = modules.vscode-server;
        };
    }
    // (let
      inherit (flake-utils.lib) defaultSystems eachSystem;
    in
      eachSystem defaultSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs.lib) hasSuffix optionalAttrs;
        auto-fix-vscode-server = pkgs.callPackage ./pkgs/auto-fix-vscode-service.nix {
          name = "server";
          installPath = "~/.vscode-server";
        };
      in
        # The package depends on `inotify-tools` which is only available on Linux.
        optionalAttrs (hasSuffix "-linux" system) {
          packages = {
            inherit auto-fix-vscode-server;
            default = auto-fix-vscode-server;
          };
          checks = {
            inherit auto-fix-vscode-server;
          };
        }));
}
