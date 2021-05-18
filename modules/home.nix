import ./module.nix ({ name, description, serviceConfig }:

{
  systemd.user.services.${name} = {
    Unit = {
      Description = description;
    };

    Service = serviceConfig;

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
})
