{pkgs, ...}:

{
  environment.systemPackages = [
    pkgs.httpie # For testing
  ];

  networking = {
    useDHCP = false;
  };

  xservices = {
    nexus = {
      enable = true;

      users = [
        {
          userId = "admin";
          firstName = "Administrator";
          lastName = "User";
          emailAddress = "admin@example.org";
          passwordFile = pkgs.writeText "admin.password" "admin";
          roles = [ "nx-admin" ];
        }
      ];

      hostedRepositories = {
        maven = [
            {
              name = "maven";
            }
        ];
      };
    };
  };

  boot.isContainer = true;
}
