{ pkgs, ... }:
let
  listenPort = 8081;
in
  pkgs.nixosTest {
    name = "nixus";

    machine = { pkgs, ... }: {
      imports = [ ./module.nix ];

      networking = {
        useDHCP = false;
      };

      xservices = {
        nexus = {
          inherit listenPort; 

          enable = true;
        };
      };

    };
    testScript = ''
        machine.wait_for_unit("nexus.service")

        with subtest("main unit is active"):
          machine.succeed("systemctl is-active --quiet nexus")
    '';
  }
