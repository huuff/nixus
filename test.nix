{ pkgs, ... }:
let
  listenPort = 8081;
  nexusHomeDir = "/var/lib/sonatype-work";
  adminPassword = "adminpassword";
  mavenRepositoryName = "test-maven-repository";
  testRole = {
    id = "test-role";
    name = "test-role";
    description = "Role to test";
    privileges = [ "nx-metrics-all" ];
    roles = [];
  };
  adminUser = {
    userId = "admin";
    firstName = "Administrator";
    lastName = "User";
    # The email address is changed from the default, so we can test
    # whether the admin user is updated
    emailAddress = "admin@nixtest.org";
    passwordFile = pkgs.writeText "admin.password" adminPassword;
    roles = [ "nx-admin"];
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
        jq # To process json inside the machine
      ];

      xservices = {
        nexus = {
          inherit listenPort; 

          enable = true;
          debug = true;

          roles = [ testRole ];

          users = [
            adminUser
          ];

          hostedRepositories = {
            maven = [
              {
                name = mavenRepositoryName;
              }
            ];
          };
        };
      };

      virtualisation = {
        memorySize = 2048;
        diskSize = 5 * 1024;
      };
    };

    extraPythonPackages = p: [ p.pyhamcrest ];
    # XXX: pyhamcrest has no types, so mypy typecheck fails
    skipTypeCheck = true;

    testScript = 
    let
      baseUrl = "http://localhost:${toString listenPort}/service/rest/v1";
    in
    ''
        import json
        from hamcrest import assert_that, equal_to

        machine.wait_for_unit("multi-user.target")

        with subtest("main unit is active"):
          machine.systemctl("is-active nexus")

        with subtest("create roles unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-roles", 300)

        with subtest("create users unit is active"):
          machine.wait_until_succeeds("systemctl is-active create-nexus-users", 100)

        with subtest("admin password is set"):
          machine.succeed("http --check-status --auth 'admin:${adminPassword}' GET 'http://localhost:${toString listenPort}/service/rest/v1/status/check'")

        with subtest("creates roles"):
          status, output = machine.execute("""\
            http \
                 --check-status \
                 --print=b \
                 --auth 'admin:${adminPassword}' \
                 GET '${baseUrl}/security/roles/${testRole.id}'
            """) 

          assert_that(status, equal_to(0))
          assert_that(json.loads(output), equal_to(json.loads("""
            {
              "id": "test-role",
              "name": "test-role",
              "description": "Role to test",
              "privileges": [ "nx-metrics-all" ],
              "roles": [],
              "source": "default"
            }
          """)))

        with subtest("admin user is updated"):
          status, output = machine.execute("""\
            http \
                --check-status \
                --print=b \
                --auth 'admin:${adminPassword}' \
                GET '${baseUrl}/security/users' \
                | jq '.[] | select(.userId == "${adminUser.userId}")'
          """)

          assert_that(status, equal_to(0))
          assert_that(json.loads(output), equal_to(json.loads("""
            {
              "userId": "admin",
              "firstName": "Administrator",
              "lastName": "User",
              "emailAddress": "admin@nixtest.org",
              "source": "default",
              "status": "active",
              "readOnly": false,
              "roles": [ "nx-admin" ],
              "externalRoles": []
            }
          """)))

          with subtest("maven repositories"):
            machine.wait_until_succeeds("systemctl is-active configure-maven-repositories", 100)
            status, output = machine.execute("""\
              http \
                --check-status \
                --print=b \
                --auth 'admin:${adminPassword}' \
                GET '${baseUrl}/repositories/maven/hosted/${mavenRepositoryName}'
            """)

            assert_that(status, equal_to(0))
            assert_that(json.loads(output), equal_to(json.loads("""
              {
                "name": "${mavenRepositoryName}",
                "online": true,
                "url": "http://localhost:8081/repository/${mavenRepositoryName}",
                "storage": {
                  "blobStoreName": "default",
                  "strictContentTypeValidation": true,
                  "writePolicy": "ALLOW"
                },
                "cleanup": null,
                "maven": {
                  "versionPolicy": "MIXED",
                  "layoutPolicy": "STRICT",
                  "contentDisposition": "INLINE"
                },
                "component": {
                  "proprietaryComponents": false
                },
                "format": "maven2",
                "type": "hosted"
              }
            """)))
    '';
  }
