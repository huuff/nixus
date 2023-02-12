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

    # TODO: This in a separate file
    nixosConfigurations.container = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ({pkgs, ...}: {
          imports = [ self.nixosModules.nexus ];

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
        })
      ];
    };
  };
}
