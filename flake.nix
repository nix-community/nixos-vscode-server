{
  description = "NixOS VSCode server";

  outputs = { self, nixpkgs }: {
    nixosModule = import ./modules/vscode-server;
    nixosModules.default = self.nixosModule;
    homeManagerModule = import ./modules/vscode-server/home.nix;
    homeManagerModules.default = self.homeManagerModule;
  };
}
