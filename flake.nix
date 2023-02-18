{
  description = "A very basic flake";

  inputs = {
    #nixpkgs.url = "nixpkgs/nixos-22.05";
    # XXX: Only unstable currently has nexus > 3.4.0
    # which includes a privilege for healthchecks I need for my tests
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    # TODO: Add "deault" pointing to "nix"
    nixosModules = {
      nexus = import ./module.nix;

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
