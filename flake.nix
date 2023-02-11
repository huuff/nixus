{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.05";
  };

  outputs = { self, nixpkgs }:
  {
    nixosModules = {
      nexus = import ./module.nix;

    };

    nixosConfigurations.container = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        {
          imports = [ self.nixosModules.nexus ];

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
      ];
    };
  };
}
