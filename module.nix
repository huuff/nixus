
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
          description = "Create a Nexus user that can interact with the API to reconcile state with the NixOS configuration";

          wantedBy = [ "multi-user.target" ];

          partOf = [ "nexus.service" ];
          after = [ "nexus.service" ];

          path = [ pkgs.httpie ];

          # TODO: Do this with an inline JSON, it's cleaner
          # TODO: If admin doesn't work (401), skip it
          # TODO: Create a mostly-read-only role for the user
          script = ''
            admin_password=$(cat "${cfg.home}/nexus3/admin.password")
            echo "The admin password is $admin_password"
            http -a "admin:$admin_password" --ignore-stdin POST http://localhost:8081/service/rest/v1/security/users \
              "userId=nix" \
              "firstName=Nix" \
              "lastName=User" \
              "emailAddress=user@nix.com" \
              "status=active" \
              "password=$admin_password" \
              'roles:=[ "nx-anonymous" ]'
          '';

          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 5;
            Type = "oneshot";
          };
        };
      };
    };

    meta.maintainers = with lib.maintainers; [ ironpinguin ];
  }
