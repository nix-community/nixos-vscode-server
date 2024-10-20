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
    (lib.mkIf cfg.enableForUsers.enable {
      systemd.tmpfiles.settings =
        let
          forEachUser = ({ path, file }: builtins.listToAttrs
            (builtins.map
              (username: let user = config.users.users.${username}; in {
                name = "${user.home}/${path}";
                value = file user.name;
              })
              cfg.enableForUsers.users));
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
          "80-vscode-server-enable-for-users-create-config-folder" = homeDirectory ".config";
          "81-vscode-server-enable-for-users-create-systemd-folder" = homeDirectory ".config/systemd";
          "82-vscode-server-enable-for-users-create-systemd-user-folder" = homeDirectory ".config/systemd/user";
          "83-vscode-server-enable-for-users-enable-auto-fix-vscode-server-service" = forEachUser {
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
