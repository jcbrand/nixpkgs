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
    LocalSocket ${runDir}/clamd.ctl
    FixStaleSocket true
    LocalSocketGroup clamav
    LocalSocketMode 666
    # TemporaryDirectory is not set to its default /tmp here to make overriding
    # the default with environment variables TMPDIR/TMP/TEMP possible
    User clamav
    AllowSupplementaryGroups true
    ScanMail true
    ScanArchive true
    ArchiveBlockEncrypted false
    MaxDirectoryRecursion 15
    FollowDirectorySymlinks false
    FollowFileSymlinks false
    ReadTimeout 180
    MaxThreads 12
    MaxConnectionQueueLength 15
    LogSyslog false
    LogRotate true
    LogFacility LOG_LOCAL6
    LogClean false
    LogVerbose false
    PidFile ${runDir}/clamd.pid
    DatabaseDirectory ${stateDir}/clamav
    SelfCheck 3600
    Foreground false
    Debug false
    ScanPE true
    MaxEmbeddedPE 10M
    ScanOLE2 true
    ScanPDF true
    ScanHTML true
    MaxHTMLNormalize 10M
    MaxHTMLNoTags 2M
    MaxScriptNormalize 5M
    MaxZipTypeRcg 1M
    ScanSWF true
    DetectBrokenExecutables false
    ExitOnOOM false
    LeaveTemporaryFiles false
    AlgorithmicDetection true
    ScanELF true
    IdleTimeout 30
    PhishingSignatures true
    PhishingScanURLs true
    PhishingAlwaysBlockSSLMismatch false
    PhishingAlwaysBlockCloak false
    PartitionIntersection false
    DetectPUA false
    ScanPartialMessages false
    HeuristicScanPrecedence false
    StructuredDataDetection false
    CommandReadTimeout 5
    SendBufTimeout 200
    MaxQueue 100
    ExtendedDetectionInfo true
    OLE2BlockMacros false
    ScanOnAccess false
    AllowAllMatchScan true
    ForceToDisk false
    DisableCertCheck false
    DisableCache false
    MaxScanSize 100M
    MaxFileSize 25M
    MaxRecursion 10
    MaxFiles 10000
    MaxPartitions 50
    MaxIconsPE 100
    StatsEnabled false
    StatsPEDisabled true
    StatsHostID auto
    StatsTimeout 10
    StreamMaxLength 25M
    LogFile ${logDir}/clamav.log
    LogTime true
    LogFileUnlock false
    LogFileMaxSize 0
    Bytecode true
    BytecodeSecurity TrustSigned
    BytecodeTimeout 60000
    OfficialDatabaseOnly false
    CrossFilesystems true

    ${cfg.daemon.extaConfig}
  '';
in
{
  ###### interface

  options = {

    services.clamav = {
      daemon = {
        extraConfig = mkOption {
          default = "";
          description = ''
            Exra configuration for clamd. Contents will be added verbatim to the
            configuration file.
          '';
        };
      },
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

  config = mkIf cfg.updater.enable {
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

    services.clamav.updater.config = ''
      DatabaseDirectory ${stateDir}
      Foreground yes
      Checks ${toString cfg.updater.frequency}
      DatabaseMirror database.clamav.net
    '';

    jobs = {
      clamav_daemon = {
	      name = "clamav-daemon";
        startOn = "startup";

        preStart = ''
          mkdir -m 0755 -p ${logDir}
          mkdir -m 0755 -p ${runDir}
          chown ${clamavUser}:${clamavGroup} ${logDir}
          chown ${clamavUser}:${clamavGroup} ${runDir}
          '';
        exec = "${pkgs.clamav}/bin/clamd";
      }; 
      clamav_updater = {
	      name = "clamav-updater";
        startOn = "started network-interfaces";
        stopOn = "stopping network-interfaces";

        preStart = ''
          mkdir -m 0755 -p ${stateDir}
          chown ${clamavUser}:${clamavGroup} ${stateDir}
          '';
        exec = "${pkgs.clamav}/bin/freshclam --daemon --config-file=${pkgs.writeText "freshclam.conf" cfg.updater.config}";
      }; 
    };
  };
}
