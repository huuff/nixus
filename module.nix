
{ config, lib, pkgs, ... }:

with lib;

# TODO: I'm not handling passwords changing yet.
# TODO: Maybe add set +x, set -x only around scripts that need failing status codes?
let
  cfg = config.xservices.nexus;
  apiUrl = "http://localhost:${toString cfg.listenPort}/service/rest/v1";
  hostedStorageAttributesModule = with types; submodule {
    options = {
      blobStoreName = mkOption {
        type = str;
        default = "default";
        description = "Blob store used to store repository contents";
      };

      strictContentTypeValidation = mkOption {
        type = bool;
        default = true;
        description = "Whether to validate uploaded content's MIME type appropriate for the repository format";
      };

      writePolicy = mkOption {
        type = enum [ "ALLOW" "ALLOW_ONCE" "DENY" ];
        default = "ALLOW";
        description = "Controls if deployments of and updates to assets are allowed";
      };
    };
  };
  roleModule = with types; submodule {
    options = {
      id = mkOption {
        type = str;
        description = "The id of the role";
      };
      name = mkOption {
        type = str;
        description = "The name of the role";
      };
      description = mkOption {
        type = str;
        description = "The description of this role";
      };
      privileges = mkOption {
        type = listOf str;
        description = "The list of privileges assigned to this role";
      };
      roles = mkOption {
        type = listOf str;
        default = [];
        description = "The list of roles assigned to this role";
      };
    };
  };

  userModule = with types; submodule {
    options = {
      userId = mkOption {
        type = str;
        description = "The userid which is required for login. This value cannot be changed";
      };

      firstName = mkOption {
        type = str;
        description = "The first name of the user";
      };

      lastName = mkOption {
        type = str;
        description = "The last name of the user";
      };

      emailAddress = mkOption {
        type = str;
        description = "The email address associated with the user";
      };

      passwordFile = mkOption {
        type = oneOf [ path str ];
        description = "Path to the file that contains this user's password";
      };

      status = mkOption {
        type = enum [ "active" "locked" "disabled" "changepassword"];
        description = "The user's status, e.g. active or disabled";
        default = "active";
      };

      roles = mkOption {
        type = listOf str;
        description = "The roles which the user has been assigned within Nexus.";
        default = [];
      };
    };
  };

  mavenHostedRepositoryModule = with types; submodule {
    options = {
      name = mkOption {
        type = str;
        description = "A unique identifier for this repository";
      };

      online = mkOption {
        type = bool;
        default = true;
        description = "Whether this repository accepts incoming requests";
      };

      storage = mkOption {
        type = hostedStorageAttributesModule;
        default = {};
      };

      maven = mkOption {
        type = submodule {
          options = {
            contentDisposition = mkOption {
              type = enum [ "INLINE" "ATTACHMENT" ];
              description = "Content Disposition";
              default = "INLINE";
            };

            versionPolicy = mkOption {
              type = enum [ "RELEASE" "SNAPSHOT" "MIXED"];
              description = "What type of artifacts does this repository store?";
              default = "MIXED";
            };

            layoutPolicy = mkOption {
              type = enum [ "STRICT" "PERMISSIVE" ];
              description = "Validate that all paths are maven artifact or metadata paths";
              default = "STRICT";
            };
          };
        };
        default = {};
      };
    };
  };
  adminUser = findFirst (it: it.userId == "admin") null cfg.users;
  shellScripts = {
    # TODO: Wait for this in a specific unit that runs before any other
    exitIfNexusIsNotStarted = ''http --quiet --check-status GET "${apiUrl}/status" > /dev/null || { echo "Nexus not started"; exit 1; }'';

    # Creates $user and $password variables that hold the credentials to make requests to the API.
    setUpCredentials = ''
      if [ -f "${cfg.home}/nexus3/admin.password" ]; then
        user="admin"
        password="$(cat "${cfg.home}/nexus3/admin.password")"
        echo "Using admin user with initial password"
      else
        ${if adminUser != null
          then ''
            user="admin"
            password="$(cat ${toString adminUser.passwordFile})"
            echo "Using admin user with provided password"
          ''
          else ''
            echo "No API user exists, the initial admin password file doesn't exist and the admin user is not provided in the nix configuration. This should never had happened and you should report this as an issue."
          ''}
      fi
    '';
  };
  # --quiet argument only if debug is false, otherwise it's the empty string
  # useful for enabling/disabling logging in httpie commands
  optionalQuiet = optionalString (!cfg.debug) "--quiet";
in

  {
    options = {
      xservices.nexus = with types; {
        enable = mkEnableOption (lib.mdDoc "Sonatype Nexus3 OSS service");

        package = mkOption {
          type = package;
          default = pkgs.nexus;
          defaultText = literalExpression "pkgs.nexus";
          description = mdDoc "Package which runs Nexus3";
        };

        user = mkOption {
          type = str;
          default = "nexus";
          description = mdDoc "User which runs Nexus3.";
        };

        group = mkOption {
          type = str;
          default = "nexus";
          description = mdDoc "Group which runs Nexus3.";
        };

        home = mkOption {
          type = str;
          default = "/var/lib/sonatype-work";
          description = mdDoc "Home directory of the Nexus3 instance.";
        };

        listenAddress = mkOption {
          type = str;
          default = "0.0.0.0";
          description = lib.mdDoc "Address to listen on.";
        };

        listenPort = mkOption {
          type = int;
          default = 8081;
          description = mdDoc "Port to listen on.";
        };

        hostedRepositories = {
          maven = mkOption {
            type = listOf mavenHostedRepositoryModule;
            default = [];
            description = "List of Maven hosted modules to create by default";
          };
        };

        roles = mkOption {
          type = listOf roleModule;
          default = [];
          description = "List of roles to create by default";
        };

        users = mkOption {
          type = listOf userModule;
          default = [];
          description = "List of users to create by default";
        };

        jvmOpts = mkOption {
          type = lines;
          default = ''
            -Xms1200M
            -Xmx1200M
            -XX:MaxDirectMemorySize=2G
            -XX:+UnlockDiagnosticVMOptions
            -XX:+UnsyncloadClass
            -XX:+LogVMOutput
            -XX:LogFile=${cfg.home}/nexus3/log/jvm.log
            -XX:-OmitStackTraceInFastThrow
            -Djava.net.preferIPv4Stack=true
            -Dkaraf.home=${cfg.package}
            -Dkaraf.base=${cfg.package}
            -Dkaraf.etc=${cfg.package}/etc/karaf
            -Djava.util.logging.config.file=${cfg.package}/etc/karaf/java.util.logging.properties
            -Dkaraf.data=${cfg.home}/nexus3
            -Djava.io.tmpdir=${cfg.home}/nexus3/tmp
            -Dkaraf.startLocalConsole=false
            -Djava.endorsed.dirs=${cfg.package}/lib/endorsed
          '';
          defaultText = literalExpression ''
            '''
            -Xms1200M
            -Xmx1200M
            -XX:MaxDirectMemorySize=2G
            -XX:+UnlockDiagnosticVMOptions
            -XX:+UnsyncloadClass
            -XX:+LogVMOutput
            -XX:LogFile=''${home}/nexus3/log/jvm.log
            -XX:-OmitStackTraceInFastThrow
            -Djava.net.preferIPv4Stack=true
            -Dkaraf.home=''${package}
            -Dkaraf.base=''${package}
            -Dkaraf.etc=''${package}/etc/karaf
            -Djava.util.logging.config.file=''${package}/etc/karaf/java.util.logging.properties
            -Dkaraf.data=''${home}/nexus3
            -Djava.io.tmpdir=''${home}/nexus3/tmp
            -Dkaraf.startLocalConsole=false
            -Djava.endorsed.dirs=''${package}/lib/endorsed
            '''
          '';

          description = mdDoc ''
            Options for the JVM written to `nexus.jvmopts`.
            Please refer to the docs (https://help.sonatype.com/repomanager3/installation/configuring-the-runtime-environment)
            for further information.
          '';
        };

        debug = mkOption {
          type = bool;
          default = false;
          description = "Enables logging debug statements in systemd units and scripts. Should be disabled unless testing since these may leak sensitive information";
        };
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = adminUser != null;
          message = "There must be an user with userId 'admin' declared.";
        }
        {
          assertion = adminUser.roles == [] || elem "nx-admin" adminUser.roles;
          message = "The 'roles' attribute of the admin user must be empty or contain 'nx-admin'";
        }
      ];

      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.home;
        createHome = true;
      };

      users.groups.${cfg.group} = {};

      networking.firewall.allowedTCPPorts = [ cfg.listenPort ];

      systemd.services = {
        nexus = {
          description = "Sonatype Nexus3";

          wantedBy = [ "multi-user.target" ];

          path = [ cfg.home ];

          environment = {
            NEXUS_USER = cfg.user;
            NEXUS_HOME = cfg.home;

            VM_OPTS_FILE = pkgs.writeText "nexus.vmoptions" cfg.jvmOpts;
          };

          preStart = ''
            mkdir -p ${cfg.home}/nexus3/etc
            if [ ! -f ${cfg.home}/nexus3/etc/nexus.properties ]; then
              echo "# Jetty section" > ${cfg.home}/nexus3/etc/nexus.properties
              echo "application-port=${toString cfg.listenPort}" >> ${cfg.home}/nexus3/etc/nexus.properties
              echo "application-host=${toString cfg.listenAddress}" >> ${cfg.home}/nexus3/etc/nexus.properties
            else
              sed 's/^application-port=.*/application-port=${toString cfg.listenPort}/' -i ${cfg.home}/nexus3/etc/nexus.properties
              sed 's/^# application-port=.*/application-port=${toString cfg.listenPort}/' -i ${cfg.home}/nexus3/etc/nexus.properties
              sed 's/^application-host=.*/application-host=${toString cfg.listenAddress}/' -i ${cfg.home}/nexus3/etc/nexus.properties
              sed 's/^# application-host=.*/application-host=${toString cfg.listenAddress}/' -i ${cfg.home}/nexus3/etc/nexus.properties
            fi
          '';

          script = "${cfg.package}/bin/nexus run";

          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            PrivateTmp = true;
            LimitNOFILE = 102642;
          };
        };

        # TODO: Test
        # TODO: Update them if they already exist
        # TODO: Maybe re-enable set -e for the creation api calls
        create-nexus-roles = {
          description = "Nexus roles creation";

          wantedBy = [ "multi-user.target"];

          partOf = [ "nexus.service"];
          after = [ "nexus.service"];

          path = [ pkgs.httpie ];

          script = ''
            set +e

            ${shellScripts.exitIfNexusIsNotStarted}
            ${shellScripts.setUpCredentials}

            ${concatMapStringsSep "\n" (module: ''
              echo "Creating ${module.name} role"
              http ${optionalQuiet} \
                   --check-status \
                   --auth "$user:$password" \
                   POST "${apiUrl}/security/roles" <<< '${builtins.toJSON module}'
            '') cfg.roles}
          '';

          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 15;
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        # TODO: Test
        # TODO: A better name, since it also updates users
        # TODO: Update admin is breaking because no roles are provided? Kinda obvious, since I'm setting the roles in the "adminUser" but not in the users array
        create-nexus-users = {
          description = "Nexus users creation";

          wantedBy = [ "multi-user.target" ];

          # TODO: Maybe use `requires`?
          partOf = [ "create-nexus-roles.service"];
          after = [ "create-nexus-roles.service"];

          path = with pkgs; [
            httpie
            jq
          ];

          # TODO: I'm inlining the JSON because the password needs special treatment (getting it in bash)
          # can't I just create one JSON with toJSON for the other properties and merge it dynamically (maybe with jq?)
          # with one JSON with only the password, got from bash?
          script = 
          let
            # Append the nx-admin role to the admin user if it has no roles
            adminUser = 
              if adminUser.roles == []
              then adminUser // { roles = ["nx-admin"]; }
              else adminUser
              ;
          in
          ''
            set +e

            ${shellScripts.exitIfNexusIsNotStarted}
            ${shellScripts.setUpCredentials}

            ${concatMapStringsSep "\n" (module: ''
              user_exists=$( \
                http ${optionalQuiet} \
                     --ignore-stdin \
                     --auth "$user:$password" \
                     GET "${apiUrl}/security/users" \
                     | jq '.[] | select(.userId == "${module.userId}")' \
              )

              if [ -z "$user_exists" ]
              then
                echo "Creating ${module.userId} user"
                http ${optionalQuiet} \
                     --check-status \
                     --auth "$user:$password" \
                     POST "${apiUrl}/security/users" <<EOF
                  {
                    "userId": "${module.userId}",
                    "firstName": "${module.firstName}",
                    "lastName": "${module.lastName}",
                    "emailAddress": "${module.emailAddress}",
                    "status": "${module.status}",
                    "password": "$(cat "${toString module.passwordFile}")",
                    "roles": [
                      ${concatMapStringsSep "," (role: ''"${role}"'') module.roles}
                    ]
                  }
              EOF
              else
                echo "Updating user ${module.userId}"
                http ${optionalQuiet} \
                     --check-status \
                     --auth "$user:$password" \
                        PUT "${apiUrl}/security/users/${module.userId}" <<EOF
                      {
                        "userId": "${module.userId}",
                        "firstName": "${module.firstName}",
                        "lastName": "${module.lastName}",
                        "emailAddress": "${module.emailAddress}",
                        "status": "${module.status}",
                        "source": "default",
                        "password": "$(cat "${toString module.passwordFile}")",
                        "roles": [
                          ${concatMapStringsSep "," (role: ''"${role}"'') module.roles}
                        ]
                      }
              EOF
                echo "Updating password for user ${module.userId}"
                http ${optionalQuiet} \
                      --check-status \
                      --auth "$user:$password" \
                      PUT "${apiUrl}/security/users/${module.userId}/change-password" Content-Type:text/plain < "${module.passwordFile}"

              fi

              # Loading credentials again in case we just changed
              # the admin's
              ${shellScripts.setUpCredentials}
            '') cfg.users}
          '';

          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 15;
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        configure-maven-repositories = {
          description = "Configure Maven repositories";

          wantedBy = [ "multi-user.target"];
          requires = [ "create-nexus-users.service"];
          after = [ "create-nexus-users.service"];

          path = [ pkgs.httpie ];

          # TODO: Test
          # TODO: This should get activated when create-nexus-api-user gets activated, but currently it fails (I'm starting it manually in the demo container)
          # TODO: Also updating repositories if they already exist
          script = 
          ''
          set +e

          ${shellScripts.setUpCredentials}

          ${concatMapStringsSep "\n" (module: ''
              http ${optionalQuiet} \
                   --check-status \
                   --auth "$user:$password" \
                   GET "${apiUrl}/repositories/maven/hosted/${module.name}"

              return_code="$?"

              if [ "$return_code" -eq 4 ]; then
              http ${optionalQuiet} \
                   --check-status \
                   --auth "$user:$password" \
                   POST "${apiUrl}/repositories/maven/hosted/" <<EOF
                {
                  "name": "${module.name}",
                  "online": ${toString module.online},
                  "storage": {
                    "blobStoreName": "${module.storage.blobStoreName}",
                    "writePolicy": "${module.storage.writePolicy}",
                    "strictContentTypeValidation": ${toString module.storage.strictContentTypeValidation}
                  },
                  "maven": {
                    "contentDisposition": "${module.maven.contentDisposition}",
                    "versionPolicy": "${module.maven.versionPolicy}",
                    "layoutPolicy": "${module.maven.layoutPolicy}"
                  }
                }
              EOF
              else
                echo "Repository ${module.name} already exists, skipping unit"
              fi
          '') cfg.hostedRepositories.maven}
          '';

          serviceConfig = {
          Restart = "on-failure";
          RestartSec = 15;
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
    };
  };

}
