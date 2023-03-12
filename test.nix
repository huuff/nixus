{ pkgs, ... }:
let
  listenPort = 8081;
  nexusHomeDir = "/var/lib/sonatype-work";
  adminUser = {
    password = "adminpassword";
  };
  testRole = {
    id = "test-role";
    name = "test-role";
    description = "Role to test";
    privileges = [ "nx-metrics-all" ];
    roles = [];
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
          debug = true;

          roles = [ testRole ];

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

    # TODO: Test that the admin user is updated
    testScript = ''
        #import json

        machine.wait_for_unit("multi-user.target")

        with subtest("main unit is active"):
          machine.systemctl("is-active nexus")

        with subtest("create roles unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-roles", 300)

        with subtest("create users unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-users", 100)

        with subtest("admin password is set"):
          machine.succeed("http --check-status --auth 'admin:${adminUser.password}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")

        with subtest("creates roles"):
          status, output = machine.execute("""\
            http \
                 --check-status \
                 --print=b \
                 --auth 'admin:${adminUser.password}' \
                 GET 'http://localhost:${toString listenPort}/service/rest/v1/security/roles/${testRole.id}'
            """) 
          assert status == 0
          #assert json.loads(output) == json.loads('${builtins.toJSON testRole}')
    '';
  }
