{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.services.taina;
  container = config.services.beam.containers.taina;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    concatStringsSep
    mapAttrsToList
    escapeShellArg
    ;

  confLines = [
    "url_scheme = ${cfg.scheme}"
    "hostname = ${cfg.hostname}"
    "url_port = ${toString cfg.urlPort}"
    "bind_ip = 0.0.0.0"
    "port = ${toString container.port}"
    "max_blob_size = ${toString cfg.maxBlobSize}"
    "max_concurrent_uploads = ${toString cfg.maxConcurrentUploads}"
    "data_dir = /data"
    "storage_dir = /app/storage"
    "backup_dir = /app/backups"
    "backup_enabled = ${lib.boolToString cfg.backup.enable}"
    "update_check = ${lib.boolToString cfg.updateCheck}"
  ] ++ mapAttrsToList (key: value: "${key} = ${value}") cfg.settings;

  confFile = pkgs.writeText "taina.conf" (concatStringsSep "\n" confLines + "\n");

  deploymentKeys = [
    "url_scheme"
    "hostname"
    "url_port"
    "bind_ip"
    "port"
    "max_blob_size"
    "max_concurrent_uploads"
    "data_dir"
    "storage_dir"
    "backup_dir"
    "backup_enabled"
    "update_check"
  ];
  collisions = builtins.filter (key: builtins.hasAttr key cfg.settings) deploymentKeys;
  userSpec = "${toString container.uid}:${toString container.gid}";
  requiredMounts = lib.unique (container.requiredMounts ++ [ container.dataDir cfg.storageDir cfg.backupDir ]);
  storageChecks = concatStringsSep "\n" (map (path: "  require_mount ${escapeShellArg (toString path)}") container.requiredMounts);

  operator = pkgs.writeShellApplication {
    name = "taina";
    runtimeInputs = [ config.virtualisation.docker.package config.systemd.package pkgs.util-linux ];
    text = lib.replaceStrings
      [ "@IMAGE@" "@CONTAINER@" "@SERVICE@" "@DATA_DIR@" "@STORAGE_DIR@" "@CONFIG_FILE@" "@BACKUP_DIR@" "@USER_SPEC@" "@STORAGE_CHECKS@" ]
      [
        (escapeShellArg container.image)
        (escapeShellArg "taina")
        (escapeShellArg "taina")
        (escapeShellArg container.dataDir)
        (escapeShellArg cfg.storageDir)
        (escapeShellArg confFile)
        (escapeShellArg cfg.backupDir)
        (escapeShellArg userSpec)
        storageChecks
      ]
      (builtins.readFile ./operator.sh);
  };
in
{
  options.services.taina = {
    hostname = mkOption { type = types.str; example = "community.example.org"; };
    scheme = mkOption { type = types.enum [ "http" "https" ]; default = "https"; };
    urlPort = mkOption { type = types.port; default = if cfg.scheme == "http" then 80 else 443; };
    maxBlobSize = mkOption { type = types.int; default = 2 * 1024 * 1024 * 1024; };
    maxConcurrentUploads = mkOption { type = types.int; default = 10; };
    storageDir = mkOption { type = types.path; default = "/var/lib/taina-storage"; };
    backupDir = mkOption { type = types.path; default = "/var/lib/taina-backups"; };
    backup.enable = mkEnableOption "scheduled backups";
    updateCheck = mkOption { type = types.bool; default = false; };
    settings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Uncommon taina.conf keys. Module-owned keys are rejected.";
    };
  };

  config = lib.mkMerge [
    {
      services.beam.containers.taina = {
        entrypoint = "/app/bin/server";
        cmd = [ ];
        environment.TAINA_CONFIG = "/data/taina.conf";
        volumes = [
          "${cfg.storageDir}:/app/storage"
          "${cfg.backupDir}:/app/backups"
          "${confFile}:/data/taina.conf:ro"
        ];
      };
    }
    (mkIf container.enable {
      assertions = [
        { assertion = container.port != null; message = "services.beam.containers.taina.port must be set."; }
        { assertion = collisions == [ ]; message = "services.taina.settings must not set module-owned keys: ${concatStringsSep ", " collisions}."; }
        { assertion = cfg.maxBlobSize > 0; message = "services.taina.maxBlobSize must be positive."; }
        { assertion = cfg.maxConcurrentUploads > 0; message = "services.taina.maxConcurrentUploads must be positive."; }
      ];

      systemd.tmpfiles.rules = [
        "d '${cfg.storageDir}' 0750 taina taina -"
        "d '${cfg.backupDir}' 0750 taina taina -"
      ];

      systemd.services.taina-backup = {
        description = "Taina backup";
        unitConfig.RequiresMountsFor = requiredMounts;
        serviceConfig = { Type = "oneshot"; ExecStart = "${operator}/bin/taina backup"; };
      };
      environment.systemPackages = [ operator ];
    })
  ];
}
