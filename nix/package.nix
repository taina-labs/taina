# The taina release, built from source with the beam toolchain nixpkgs ships.
#
# taina needs Elixir 1.20 on OTP 28. The pinned nixpkgs' beam scope predates
# 1.20 (it tops out at 1.18), so the elixir-overlay input builds both and the
# scope is extended to use them. `extend` is makeExtensible's API, stable
# across nixpkgs versions, unlike overrideScope which the beam scope did not
# have yet in the pinned release.
#
# Two native pieces are pinned to the build rather than fetched at build time,
# which the sandbox forbids:
#
#   - esbuild: `mix assets.deploy` drives the esbuild hex package, pointed at
#     nixpkgs' binary through ESBUILD_BINARY_PATH.
#   - libvips: `vix` (behind `image`, the Ybira rendition pipeline) is told to
#     compile against the system libvips instead of downloading a precompiled
#     NIF.
{
  lib,
  beamPackages,
  elixir-with-otp,
  erlang_28,
  openssl,
  vips,
  esbuild,
  pkg-config,
}: let
  packages = beamPackages.extend (_final: _prev: {
    erlang = erlang_28;
    elixir = (elixir-with-otp erlang_28)."1.20.0";
  });

  # Read the version from mix.exs so the release bump is the only place it
  # lives. A miss falls back to 0.0.0 rather than failing the eval.
  version = let
    line = lib.findFirst (l: lib.hasInfix "version:" l) "" (lib.splitString "\n" (builtins.readFile ../mix.exs));
    matched = builtins.match ".*\"([^\"]+)\".*" line;
  in
    if matched == null
    then "0.0.0"
    else builtins.head matched;

  # Only what mix needs to build: the flake's own source, minus the state and
  # build directories a working checkout carries, and minus the assets that
  # `mix assets.deploy` regenerates inside the sandbox.
  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: _type: let
      base = baseNameOf (toString path);
    in
      !(builtins.elem base [
        "_build"
        "deps"
        "tmp"
        ".git"
        ".expert"
        ".nix-mix"
        "plts"
        "result"
        ".direnv"
      ])
      && !(lib.hasSuffix "/priv/static/assets" (toString path))
      && base != "cache_manifest.json";
  };
in
  packages.mixRelease {
    pname = "taina";
    inherit version src;

    # One fixed-output derivation for the hex deps, pinned by hash. Bumping
    # mix.lock changes the hash; the first build prints the one to paste here.
    mixFodDeps = packages.fetchMixDeps {
      pname = "taina-deps";
      inherit version src;
      hash = "sha256-M4SYxC4VleFBcVNGD0QVtFIS0SPxYptA4EYivs2KIT0=";
    };

    nativeBuildInputs = [pkg-config];
    buildInputs = [
      openssl
      vips
    ];

    # Point the esbuild hex package at nixpkgs' binary so neither the dep's
    # install step nor `mix assets.deploy` reaches for the network.
    ESBUILD_BINARY_PATH = "${esbuild}/bin/esbuild";
    # `vix` compiles a NIF against the libvips in buildInputs.
    VIX_COMPILATION_MODE = "PLATFORM_PROVIDED_LIBVIPS";

    # Deps compile in mixRelease's configurePhase, so the force_build switch has
    # to be in place before then (preBuild would be too late). exqlite's
    # elixir_make would otherwise try to download a precompiled NIF, which the
    # sandbox forbids (and its read-only HOME aborts before the source fallback).
    preConfigure = ''
          cat >> config/config.exs <<EOF

      config :elixir_make, :force_build, exqlite: true
      EOF
    '';

    # Build and digest the assets before installPhase's `mix release` copies
    # priv/ into the release. postBuild runs after `mix compile`.
    postBuild = "mix assets.deploy";

    # nixpkgs strips releases/COOKIE from the store, which the release script
    # reads unconditionally. taina is a single node and never joins a cluster, so
    # distribution is off and the cookie is inert: it only satisfies the script.
    postInstall = ''
          for env in "$out"/releases/*/env.sh; do
            cat >> "$env" <<'EOF'

      # Set by the Nix build. taina is a single node, so distribution is off and the
      # cookie exists only because the release script reads it unconditionally.
      export RELEASE_DISTRIBUTION="none"
      export RELEASE_COOKIE="taina"
      EOF
          done
    '';

    meta = {
      description = "The community private-cloud server";
      homepage = "https://github.com/taina-labs/taina";
      license = lib.licenses.agpl3Only;
      platforms = lib.platforms.unix;
    };
  }
