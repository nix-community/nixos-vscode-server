import ./module.nix ({ name, description, serviceConfig }:

{
  systemd.user.services.${name} = {
    inherit description serviceConfig;
    wantedBy = [ "default.target" ];
  };
})
