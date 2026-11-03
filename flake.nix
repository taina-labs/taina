{
  description = "taina: the community private-cloud server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    beam-overlay.url = "github:zeeetech/beam-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    beam-overlay,
  }: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (nixpkgs.lib.systems) flakeExposed;

    forAllSystems = f:
      genAttrs flakeExposed (
        system: let
          overlays = [beam-overlay.overlays.default];
          pkgs = import nixpkgs {inherit system overlays;};
        in
          f pkgs
      );
  in {
    nixosModules = {
      taina = import ./nix/module.nix;
      default = self.nixosModules.taina;
    };

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        name = "taina-dev";
        packages = with pkgs; [
          (pkgs.beam-overlay.mkToolchain {
            elixir.version = "1.20.0";
          })
          erlang_28
          just
          # Ybira renditions (thumbnails/EXIF) via image/vix → libvips.
          # On darwin vix uses its precompiled NIF; on NixOS/Pi point vix at
          # this system libvips (VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS).
          vips
          pkg-config
        ];
      };
    });
  };
}
