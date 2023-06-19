import ./module.nix ({
  name,
  description,
  serviceConfig,
}: {
  systemd.user.services.${name} = {
    enable = true;
    inherit description serviceConfig;
    wantedBy = [ "default.target" ];
  };
})
