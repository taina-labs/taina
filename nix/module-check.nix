{ nixpkgs, module }:
let
  system = "x86_64-linux";
  evaluated = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      module
      {
        system.stateVersion = "26.05";
        services.taina = {
          enable = true;
          image = "ghcr.io/taina-labs/taina:v0.6.1";
          hostname = "community.example.org";
          scheme = "http";
          listenAddress = "127.0.0.1";
          port = 4014;
          uid = 993;
          gid = 993;
          dataDir = "/zdata/taina";
          storageDir = "/zdata/ybira";
          backupDir = "/zdata/backups/taina";
          requiredMounts = [ "/zdata/taina" "/zdata/ybira" "/zdata/backups" ];
           maxBlobSize = 104857600;
           maxConcurrentUploads = 3;
           backup.enable = true;
        };
      }
    ];
  };
  config = evaluated.config;
  container = config.virtualisation.oci-containers.containers.taina;
  confVolume = nixpkgs.lib.findFirst (volume: nixpkgs.lib.hasSuffix ":/app/taina.conf:ro" volume)
    (throw "generated taina.conf volume is missing") container.volumes;
  confFile = nixpkgs.lib.removeSuffix ":/app/taina.conf:ro" confVolume;
  wrapper = nixpkgs.lib.findFirst (package: nixpkgs.lib.getName package == "taina")
    (throw "the taina operator wrapper is missing") config.environment.systemPackages;
in {
  result = assert config.virtualisation.oci-containers.backend == "docker";
    assert config.virtualisation.docker.enable;
    assert container.serviceName == "taina";
    assert container.entrypoint == "/app/bin/server";
    assert container.user == "993:993";
    assert container.environment.TAINA_CONFIG == "/app/taina.conf";
    assert container.ports == [ "127.0.0.1:4014:4000" ];
    assert nixpkgs.lib.any (x: nixpkgs.lib.hasInfix ":/app/data" x) container.volumes;
     assert nixpkgs.lib.hasInfix "max_blob_size = 104857600" (builtins.readFile confFile);
     assert nixpkgs.lib.hasInfix "max_concurrent_uploads = 3" (builtins.readFile confFile);
    assert config.users.users.taina.uid == 993;
    assert config.users.groups.taina.gid == 993;
    assert nixpkgs.lib.hasInfix "mountpoint -q /zdata/taina" config.systemd.services.taina.preStart;
    assert config.systemd.services.taina-backup.serviceConfig.Type == "oneshot";
    assert nixpkgs.lib.hasInfix "/bin/taina backup" config.systemd.services.taina-backup.serviceConfig.ExecStart;
    "taina module evaluation passed";
  inherit wrapper;
}
