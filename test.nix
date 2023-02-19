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
          machine.systemctl("is-active nexus")

        with subtest("creates user"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-api-user", 300)
          machine.succeed("http --check-status -a '${apiUser.name}:${apiUser.password}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")

          # TODO: Check whether output contains text saying user already exists?
        with subtest("create user is idempotent (exits successfully if user already exists)"):
          machine.systemctl("restart create-nexus-api-user")
          machine.wait_until_succeeds("systemctl is-active create-nexus-api-user", 15)
          machine.systemctl("is-active create-nexus-api-user")
          
    '';
  }
