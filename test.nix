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

      virtualisation = {
        memorySize = 2048;
        diskSize = 5 * 1024;
      };
    };
    testScript = ''
        machine.wait_for_unit("multi-user.target")

        with subtest("main unit is active"):
          machine.succeed("systemctl is-active --quiet nexus")

        with subtest("creates user"):
          machine.wait_for_unit("create-nexus-api-user")
          machine.succeed("systemctl is-active --quiet create-nexus-api-user")
    '';
  }
