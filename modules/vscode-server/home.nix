import ./module.nix ({ name, description, serviceConfig, extensions }:

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

  home.file = extensions;
})
