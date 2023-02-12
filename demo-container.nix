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
    };
  };

  boot.isContainer = true;
}
