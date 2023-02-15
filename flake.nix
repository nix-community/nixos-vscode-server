{
  description = "NixOS VSCode server";

  outputs = { self, nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    auto-fix-vscode-server = pkgs.callPackage ./pkgs/auto-fix-vscode-server.nix { };
  in {
    nixosModule = import ./modules/vscode-server;
    nixosModules.default = self.nixosModule;
    nixosModules.home = import ./modules/vscode-server/home.nix;
    checks.x86_64-linux.auto-fix-vscode-server = auto-fix-vscode-server;
  };
}
