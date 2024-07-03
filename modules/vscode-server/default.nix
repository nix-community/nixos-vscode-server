import ./module.nix (
  { name
  , description
  , serviceConfig
  , lib
  , config
  , cfg
  }: lib.mkMerge [
    {
      systemd.user.services.${name} = {
        inherit description serviceConfig;
        wantedBy = [ "default.target" ];
      };
    }
    (lib.mkIf cfg.enableForAllUsers {
      systemd.tmpfiles.settings =
        let
          forEachUser = ({ path, file }: lib.attrsets.mapAttrs'
            (username: userOptions:
              {
                # Create the directory so that it has the appropriate permissions if it doesn't already exist
                # Otherwise the directive below creating the symlink would have that owned by root
                name = "${userOptions.home}/${path}";
                value = file username;
              })
            (lib.attrsets.filterAttrs (username: userOptions: userOptions.isNormalUser) config.users.users));
          homeDirectory = (path: forEachUser {
            inherit path;
            file = (username: {
              "d" = {
                user = username;
                group = "users";
                mode = "0755";
              };
            });
          });
        in
        {
          # We need to create each of the folders before the next file otherwise parents get owned by root
          "80-setup-config-folder-for-all-users" = homeDirectory ".config";
          "81-setup-systemd-folder-for-all-users" = homeDirectory ".config/systemd";
          "82-setup-systemd-user-folder-for-all-users" = homeDirectory ".config/systemd/user";
          "83-enable-auto-fix-vscode-server-service-for-all-users" = forEachUser {
            path = ".config/systemd/user/auto-fix-vscode-server.service";
            file = (username: {
              "L+" = {
                user = username;
                group = "users";
                # This path is made available by `services.vscode-server.enable = true;`
                argument = "/run/current-system/etc/systemd/user/auto-fix-vscode-server.service";
              };
            });
          };
        };
    })
  ]
)
