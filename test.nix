{ pkgs, ... }:
let
  listenPort = 8081;
  nexusHomeDir = "/var/lib/sonatype-work";
in
  pkgs.nixosTest {
    name = "nixus";

    nodes.machine = { pkgs, ... }: {
      imports = [ ./module.nix ];

      networking = {
        useDHCP = false;
      };

      environment.systemPackages = with pkgs; [
        httpie # To run tests against the API
      ];

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

        # TODO: wait_for_unit might wait 4ever
        # TODO: use machine.systemctl?
        # TODO: maybe don't hardcode nix user
        with subtest("creates user"):
          machine.wait_for_unit("create-nexus-api-user")
          machine.succeed("systemctl is-active --quiet create-nexus-api-user")
          [ _, apiUserPassword ] = machine.execute("cat '${nexusHomeDir}/nexus3/admin.password'")
          machine.succeed(f"http --check-status -a 'nix:{apiUserPassword}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")
    '';
  }
