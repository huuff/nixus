
{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.xservices.nexus;

in

  {
    options = {
      xservices.nexus = {
        enable = mkEnableOption (lib.mdDoc "Sonatype Nexus3 OSS service");

        package = mkOption {
          type = types.package;
          default = pkgs.nexus;
          defaultText = literalExpression "pkgs.nexus";
          description = lib.mdDoc "Package which runs Nexus3";
        };

        user = mkOption {
          type = types.str;
          default = "nexus";
          description = lib.mdDoc "User which runs Nexus3.";
        };

        group = mkOption {
          type = types.str;
          default = "nexus";
          description = lib.mdDoc "Group which runs Nexus3.";
        };

        home = mkOption {
          type = types.str;
          default = "/var/lib/sonatype-work";
          description = lib.mdDoc "Home directory of the Nexus3 instance.";
        };

        listenAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = lib.mdDoc "Address to listen on.";
        };

        listenPort = mkOption {
          type = types.int;
          default = 8081;
          description = lib.mdDoc "Port to listen on.";
        };

        jvmOpts = mkOption {
          type = types.lines;
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

          description = lib.mdDoc ''
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

        create-nexus-api-user = {
          description = "Nexus API user creation";

          wantedBy = [ "multi-user.target" ];

          partOf = [ "nexus.service" ];
          after = [ "nexus.service" ];

          path = [ pkgs.httpie ];

          # TODO: Test
          # TODO: I should save the default "admin.password" since it gets removed! UPDATE: Actually, I should just provide the password in the module as a file
          # TODO: This does not get restarted when nexus restarts, even though using `partOf`
          # TODO: Should check whether the admin user exists before creating it. UPDATE: Actually, checking that the admin password file doesn't exist is not enough. We need to check whether the user actually has access.
          script = ''
            http GET http://localhost:${toString cfg.listenPort}/ > /dev/null || { echo "Nexus not started"; exit 1; }

            admin_password_location="${cfg.home}/nexus3/admin.password"

            if [ -f "$admin_password_location" ]; then
              admin_password=$(cat "$admin_password_location")
              echo "Creating an API user role"
              http --check-status -a "admin:$admin_password" POST http://localhost:${toString cfg.listenPort}/service/rest/v1/security/roles <<EOF
                {
                  "id": "api-user",
                  "name": "api-user",
                  "description": "API user role for the Nexus module",
                  "privileges": [ 
                    "nx-metrics-all",
                    "nx-repository-admin-*-*-add"
                  ]
                }
            EOF
              echo "Creating the API user"
              http --check-status -a "admin:$admin_password" POST http://localhost:${toString cfg.listenPort}/service/rest/v1/security/users <<EOF
                {
                  "userId": "nix",
                  "firstName": "Nix",
                  "lastName": "User",
                  "emailAddress": "user@nix.com",
                  "status": "active",
                  "password": "$admin_password",
                  "roles": [
                    "api-user"
                  ]
                }
            EOF
            else 
              echo "The admin password has changed, so we assume that the API user has been already created"
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
