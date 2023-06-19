moduleConfig: { lib, ... }: let
  mkVSCodeService = import ../lib/mkVSCodeService.nix;
in {
  vscode-cli = mkVSCodeService "cli" { installPath = mkDefault "~/.vscode-cli/code-stable"; };
  vscode-server = mkVSCodeService "server" { installPath = mkDefault "~/.vscode-server"; };
}
