
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.xservices.nexus;
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
        default = "ALLOw";
        description = "Controls if deployments of and updates to assets are allowed";
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
      };

      maven = mkOption {
        type = submodule {
          options = {
            contentDisposition = {
              type = enum [ "INLINE" "ATTACHMENT" ];
              description = "Content Disposition";
              default = "INLINE";
            };

            versionPolicy = {
              type = enum [ "RELEASE" "SNAPSHOT" "MIXED"];
              description = "What type of artifacts does this repository store?";
              default = "MIXED";
            };

            layoutPolicy = {
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

        apiUser = {
          name = mkOption {
            type = str;
            default = "nix";
            description = mdDoc "Name of the user that will be created to manage Nexus from nix";
          };

          # TODO: Randomly create one if it doesn't exist?
          passwordFile = mkOption {
            type = oneOf [ str path ];
            default = null;
            description = "Path to the file that'll contain the Nix user's password";
          };

          role = mkOption {
            type = str;
            default = "nix-api-user";
            description = "Name of the role that'll be created for the user that'll be used to manage Nexus by nix";
          };
        };

        hostedRepositories = {
          maven = mkOption {
            type = listOf mavenHostedRepositoryModule;
            default = [];
          };
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
      };
    };

    config = mkIf cfg.enable {
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

        # TODO: XXX: This might have a problem... what if the passwordFile changes?
        # It will try to use the new password and just fail
        # Maybe I could copy the password when the user is created
        # somewhere else and check whether it changed on next runs?
        create-nexus-api-user = {
          description = "Nexus API user creation";

          wantedBy = [ "multi-user.target" ];

          partOf = [ "nexus.service" ];
          after = [ "nexus.service" ];

          path = [ pkgs.httpie ];

          script = 
          let
            baseUrl = "http://localhost:${toString cfg.listenPort}";
          in
          ''
            set +e

            http --quiet "${baseUrl}" > /dev/null || { echo "Nexus not started"; exit 1; }


            user="${cfg.apiUser.name}"
            password="$(cat "${toString cfg.apiUser.passwordFile}")"

            http --quiet \
                 --check-status \
                 --auth "$user:$password" \
                 GET ${baseUrl}/service/rest/v1/status/check

            error_code="$?"

            set -e

            if [ "$error_code" -eq 4 ]; then
              admin_password_location="${cfg.home}/nexus3/admin.password"
              admin_password=$(cat "$admin_password_location")
              echo "Creating an API user role"
              http --quiet \
                   --check-status \
                   --auth "admin:$admin_password" \
                   POST ${baseUrl}/service/rest/v1/security/roles <<EOF
                {
                  "id": "${cfg.apiUser.role}",
                  "name": "${cfg.apiUser.role}",
                  "description": "API user role for the Nexus module",
                  "privileges": [ 
                    "nx-metrics-all",
                    "nx-repository-admin-*-*-add"
                  ]
                }
            EOF
              echo "Creating the API user"
              http --quiet \
                   --check-status \
                   --auth "admin:$admin_password" \
                   POST ${baseUrl}/service/rest/v1/security/users <<EOF
                {
                  "userId": "$user",
                  "firstName": "Nix",
                  "lastName": "User",
                  "emailAddress": "user@nix.com",
                  "status": "active",
                  "password": "$password",
                  "roles": [
                    "${cfg.apiUser.role}"
                  ]
                }
            EOF
            elif [ "$error_code" -eq 0 ]; then
              echo "The API user has already been created. Skipping unit."
            else
              echo "Some unknown error happened while calling the Nexus' API: ''${error_code}xx"
            fi
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

    meta.maintainers = with lib.maintainers; [ ironpinguin ];
  }
