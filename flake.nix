{
  description = "taina: the community private-cloud server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    elixir-overlay.url = "github:zoedsoupe/elixir-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    elixir-overlay,
  }: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (nixpkgs.lib.systems) flakeExposed;

    forAllSystems = f:
      genAttrs flakeExposed (
        system: let
          overlays = [elixir-overlay.overlays.default];
          pkgs = import nixpkgs {inherit system overlays;};
        in
          f pkgs
      );
  in {
    # The release, built from source. `nix build .#taina` produces a runnable
    # bin/taina. The NixOS module lives in the oka repo, which takes this flake
    # as an input.
    packages = forAllSystems (pkgs: {
      taina = pkgs.callPackage ./nix/package.nix {};
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.taina;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        name = "taina-dev";
        packages = with pkgs; [
          (elixir-with-otp erlang_28)."1.20.0"
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
