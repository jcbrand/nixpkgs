{ config, lib, pkgs, ... }:
with lib;
let
  clamavUser = "clamav";
  stateDir = "/var/lib/clamav";
  runDir = "/var/run/clamav";
  logDir = "/var/log/clamav";
  clamavGroup = clamavUser;
  cfg = config.services.clamav;
  clamdConfigFile = pkgs.writeText "clamd.conf" ''
    DatabaseDirectory ${stateDir}
    LocalSocket ${runDir}/clamd.ctl
    LogFile ${logDir}/clamav.log
    PidFile ${runDir}/clamd.pid
    User clamav

    ${cfg.daemon.extraConfig}
  '';
in
{
  options = {
    services.clamav = {
      daemon = {
        enable = mkOption {
          default = false;
          type = types.bool;
          description = "
            Enable the clamd daemon.
          ";
        };
        extraConfig = mkOption {
          default = "";
          description = ''
            Exra configuration for clamd. Contents will be added verbatim to the
            configuration file.
          '';
        };
      };
      updater = {
        enable = mkOption {
        default = false;
        description = ''
            Whether to enable automatic ClamAV virus definitions database updates.
          '';
        };

        frequency = mkOption {
          default = 12;
          description = ''
            Number of database checks per day.
          '';
        };

        config = mkOption {
          default = "";
          description = ''
            Extra configuration for freshclam. Contents will be added verbatim to the
            configuration file.
          '';
        };
      };
    };
  };

  ###### implementation

  config = mkIf cfg.updater.enable or cfg.daemon.enable {
    environment.systemPackages = [ pkgs.clamav ];
    users.extraUsers = singleton
      { name = clamavUser;
        uid = config.ids.uids.clamav;
        description = "ClamAV daemon user";
        home = stateDir;
      };

    users.extraGroups = singleton
      { name = clamavGroup;
        gid = config.ids.gids.clamav;
      };

    services.clamav.updater.config = mkIf cfg.updater.enable ''
      DatabaseDirectory ${stateDir}
      Foreground yes
      Checks ${toString cfg.updater.frequency}
      DatabaseMirror database.clamav.net
    '';

    systemd.services.clamd = mkIf cfg.daemon.enable {
      description = "ClamAV daemon (clamd)";
      path = [ pkgs.clamav ];
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        mkdir -m 0755 -p ${logDir}
        mkdir -m 0755 -p ${runDir}
        chown ${clamavUser}:${clamavGroup} ${logDir}
        chown ${clamavUser}:${clamavGroup} ${runDir}
        '';
      serviceConfig = {
        ExecStart = "${pkgs.clamav}/bin/clamd -c ${clamdConfigFile}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitInterval = "1min";
      };
    };

    systemd.services.freshclam = mkIf cfg.updater.enable {
      description = "ClamAV updater (freshclam)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.clamav ];
      preStart = ''
        mkdir -m 0755 -p ${stateDir}
        chown ${clamavUser}:${clamavGroup} ${stateDir}
        '';
      serviceConfig = {
        ExecStart = "${pkgs.clamav}/bin/freshclam --daemon --config-file=${pkgs.writeText "freshclam.conf" cfg.updater.config}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitInterval = "1min";
      };
    };
  };
}
