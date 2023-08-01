{ lib }:
import (
  if lib ? hm
  then ./home.nix
  else ./nixos.nix
)
