{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    nixosModules = {
      nexus = import ./module.nix;
      default = self.nixosModules.nexus;
    };

    nixosConfigurations.container = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [ 
        { imports = [ self.nixosModules.nexus ]; }
        (import ./demo-container.nix) 
      ];
    };

    checks.${system} = {
      nixus = import ./test.nix { inherit pkgs; };
    };
  };
}
