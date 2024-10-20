import ./module.nix (
  { name
  , description
  , serviceConfig
  , cfg
  , ...
  }:
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

    assertions = [{
      assertion = !cfg.enableForUsers.enable;
      message = "enableForUsers.enable=true doesn't make sense when using nixos-vscode-server as a home-manager module";
    }];
  }
)
