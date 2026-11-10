{ nixpkgs, module }:
let
  system = "x86_64-linux";
  evaluated = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      module
      {
        system.stateVersion = "26.05";
        services.beam.containers.taina = {
          enable = true;
          image = "ghcr.io/taina-labs/taina:v0.7.1";
          listenAddress = "127.0.0.1";
          port = 4014;
          uid = 993;
          gid = 993;
          dataDir = "/zdata/taina";
          requiredMounts = [ "/zdata" ];
        };
        services.taina = {
          hostname = "community.example.org";
          scheme = "http";
          storageDir = "/zdata/ybira";
          backupDir = "/zdata/backups/taina";
          maxBlobSize = 104857600;
          maxConcurrentUploads = 3;
          backup.enable = true;
        };
      }
    ];
  };
  config = evaluated.config;
  container = config.virtualisation.oci-containers.containers.taina;
  confVolume = nixpkgs.lib.findFirst (volume: nixpkgs.lib.hasSuffix ":/data/taina.conf:ro" volume)
    (throw "generated taina.conf volume is missing")
    container.volumes;
  confFile = nixpkgs.lib.removeSuffix ":/data/taina.conf:ro" confVolume;
  wrapper = nixpkgs.lib.findFirst (package: nixpkgs.lib.getName package == "taina")
    (throw "the taina operator wrapper is missing")
    config.environment.systemPackages;
in
{
  result = assert config.virtualisation.oci-containers.backend == "docker";
    assert config.virtualisation.docker.enable;
    assert container.serviceName == "taina";
    assert container.entrypoint == "/app/bin/server";
    assert container.user == "993:993";
    assert container.workdir == "/data";
    assert container.environment.TAINA_CONFIG == "/data/taina.conf";
    assert container.ports == [ "127.0.0.1:4014:4014" ];
    assert builtins.elem "/zdata/taina:/data" container.volumes;
    assert builtins.elem "/zdata/ybira:/app/storage" container.volumes;
    assert builtins.elem "/zdata/backups/taina:/app/backups" container.volumes;
    assert nixpkgs.lib.hasInfix "port = 4014" (builtins.readFile confFile);
    assert nixpkgs.lib.hasInfix "data_dir = /data" (builtins.readFile confFile);
    assert nixpkgs.lib.hasInfix "max_blob_size = 104857600" (builtins.readFile confFile);
    assert nixpkgs.lib.hasInfix "max_concurrent_uploads = 3" (builtins.readFile confFile);
    assert config.users.users.taina.uid == 993;
    assert config.users.groups.taina.gid == 993;
    assert nixpkgs.lib.hasInfix "mountpoint -q /zdata" config.systemd.services.taina.preStart;
    assert config.systemd.services.taina-backup.serviceConfig.Type == "oneshot";
    assert nixpkgs.lib.hasInfix "/bin/taina backup" config.systemd.services.taina-backup.serviceConfig.ExecStart;
    assert !(config.services.taina ? enable);
    assert !(config.services.taina ? image);
    assert !(config.services.taina ? port);
    assert !(config.services.taina ? containerPort);
    assert !(config.services.taina ? dataDir);
    "taina module evaluation passed";
  inherit wrapper;
}
