{ pkgs, ... }:
let
  listenPort = 8081;
  nexusHomeDir = "/var/lib/sonatype-work";
  apiUser = {
    password = "apiuserpassword";
    name = "apiuser";
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

          apiUser = {
            name = apiUser.name;
            passwordFile = pkgs.writeText "apiuser.password" apiUser.password;
          };
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
        with subtest("creates user"):
          machine.wait_for_unit("create-nexus-api-user")
          machine.succeed("systemctl is-active --quiet create-nexus-api-user")
          machine.succeed("http --check-status -a '${apiUser.name}:${apiUser.password}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")

          # TODO: Check whether output contains text saying user already exists?
        with subtest("create user is idempotent (exits successfully if user already exists)"):
          machine.systemctl("restart create-nexus-api-user")
          machine.wait_for_unit("create-nexus-api-user")
          machine.succeed("systemctl is-active --quiet create-nexus-api-user")
          
    '';
  }
