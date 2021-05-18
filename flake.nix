{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  description = "auto-fix service for vscode-server in NixOS";
  outputs = { self, nixpkgs }: {
    nixosModules = {
      system = import ./modules;
      homeManager = import ./modules/home.nix;
    };
  };
}
