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

      apiUser = {
        passwordFile = pkgs.writeText "apiuser.password" "test";
      };

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
