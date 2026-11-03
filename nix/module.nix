{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.taina;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    optional
    concatStringsSep
    mapAttrsToList
    escapeShellArg
    ;

  confLines = [
    "url_scheme = ${cfg.scheme}"
    "hostname = ${cfg.hostname}"
    "url_port = ${toString cfg.urlPort}"
    "bind_ip = 0.0.0.0"
    "port = ${toString cfg.containerPort}"
    "max_blob_size = ${toString cfg.maxBlobSize}"
    "max_concurrent_uploads = ${toString cfg.maxConcurrentUploads}"
    "data_dir = /app/data"
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
  imageName = lib.last (lib.splitString "/" cfg.image);
  imagePinned = (lib.hasInfix ":" imageName) && !(lib.hasSuffix ":latest" cfg.image);
  userSpec = "${toString cfg.uid}:${toString cfg.gid}";
  requiredMounts = lib.unique cfg.requiredMounts;
  storageChecks = concatStringsSep "\n" (map (path: "  require_mount ${escapeShellArg (toString path)}") requiredMounts);
  storagePreStart = concatStringsSep "\n" (map (path: ''
    if ! ${pkgs.util-linux}/bin/mountpoint -q ${escapeShellArg (toString path)}; then
      echo "required mount is not available: ${toString path}" >&2
      exit 1
    fi
  '') requiredMounts);

  operator = pkgs.writeShellApplication {
    name = "taina";
    runtimeInputs = [ config.virtualisation.docker.package config.systemd.package pkgs.util-linux ];
    text = lib.replaceStrings
      [ "@IMAGE@" "@CONTAINER@" "@SERVICE@" "@DATA_DIR@" "@STORAGE_DIR@" "@CONFIG_FILE@" "@BACKUP_DIR@" "@USER_SPEC@" "@STORAGE_CHECKS@" ]
      [ (escapeShellArg cfg.image) (escapeShellArg "taina") (escapeShellArg "taina")
        (escapeShellArg cfg.dataDir) (escapeShellArg cfg.storageDir) (escapeShellArg confFile)
        (escapeShellArg cfg.backupDir) (escapeShellArg userSpec) storageChecks ]
      (builtins.readFile ./operator.sh);
  };
in {
  options.services.taina = {
    enable = mkEnableOption "Taina, a self-hosted community private cloud";
    image = mkOption { type = types.str; example = "ghcr.io/taina-labs/taina:v0.6.1"; };
    hostname = mkOption { type = types.str; example = "community.example.org"; };
    scheme = mkOption { type = types.enum [ "http" "https" ]; default = "https"; };
    urlPort = mkOption { type = types.port; default = if cfg.scheme == "http" then 80 else 443; };
    port = mkOption { type = types.port; default = 4000; };
    containerPort = mkOption { type = types.port; default = 4000; };
    listenAddress = mkOption { type = types.str; default = "127.0.0.1"; };
    maxBlobSize = mkOption { type = types.int; default = 2 * 1024 * 1024 * 1024; };
    maxConcurrentUploads = mkOption { type = types.int; default = 10; };
    uid = mkOption { type = types.int; example = 993; };
    gid = mkOption { type = types.int; example = 993; };
    dataDir = mkOption { type = types.path; default = "/var/lib/taina"; };
    storageDir = mkOption { type = types.path; default = "/var/lib/taina-storage"; };
    backupDir = mkOption { type = types.path; default = "/var/lib/taina-backups"; };
    requiredMounts = mkOption { type = types.listOf types.path; default = [ ]; };
    backup.enable = mkEnableOption "scheduled backups";
    updateCheck = mkOption { type = types.bool; default = false; };
    settings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Uncommon taina.conf keys. Module-owned keys are rejected.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = imagePinned; message = "services.taina.image must select an explicit tag or digest, not latest."; }
      { assertion = collisions == [ ]; message = "services.taina.settings must not set module-owned keys: ${concatStringsSep ", " collisions}."; }
      { assertion = cfg.maxBlobSize > 0; message = "services.taina.maxBlobSize must be positive."; }
      { assertion = cfg.maxConcurrentUploads > 0; message = "services.taina.maxConcurrentUploads must be positive."; }
    ];

    users.users.taina = {
      isSystemUser = true;
      group = "taina";
      uid = cfg.uid;
      home = cfg.dataDir;
      description = "Taina server";
    };
    users.groups.taina.gid = cfg.gid;
    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 taina taina -"
      "d '${cfg.storageDir}' 0750 taina taina -"
      "d '${cfg.backupDir}' 0750 taina taina -"
    ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.taina = {
      image = cfg.image;
      serviceName = "taina";
      entrypoint = "/app/bin/server";
      cmd = [ ];
      user = userSpec;
      workdir = "/app";
      environment.TAINA_CONFIG = "/app/taina.conf";
      volumes = [
        "${cfg.dataDir}:/app/data"
        "${cfg.storageDir}:/app/storage"
        "${cfg.backupDir}:/app/backups"
        "${confFile}:/app/taina.conf:ro"
      ];
      ports = [ "${cfg.listenAddress}:${toString cfg.port}:${toString cfg.containerPort}" ];
      log-driver = "journald";
      pull = "missing";
    };

    systemd.services.taina = {
      unitConfig.RequiresMountsFor = requiredMounts;
      preStart = storagePreStart;
    };
    systemd.services.taina-backup = {
      description = "Taina backup";
      unitConfig.RequiresMountsFor = requiredMounts;
      serviceConfig = { Type = "oneshot"; ExecStart = "${operator}/bin/taina backup"; };
    };
    environment.systemPackages = [ operator ];
  };
}
