{ pkgs, ... }:
let
  listenPort = 8081;
  nexusHomeDir = "/var/lib/sonatype-work";
  adminUser = {
    password = "adminpassword";
  };
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

          roles = [
            {
              id = "test-role";
              name = "test-role";
              description = "Role to test";
              privileges = [
                "nx-metrics-all"
              ];
              roles = [];
            }
          ];

          users = [
            {
              userId = "admin";
              firstName = "Administrator";
              lastName = "User";
              emailAddress = "admin@example.org";
              passwordFile = pkgs.writeText "admin.password" adminUser.password;
            }
          ];
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
          machine.systemctl("is-active nexus")

        with subtest("create roles unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-roles", 300)

        with subtest("create users unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-users", 100)

        with subtest("admin password is set"):
          machine.succeed("http --check-status -a 'admin:${adminUser.password}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")
    '';
  }
