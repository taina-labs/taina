# Find eligible builder and runner images on Docker Hub. We use Debian instead
# of Alpine to avoid DNS resolution issues in production.
#
# Versions are pinned to match CI (.github/workflows/ci.yml): Elixir 1.20.0,
# OTP 28, so the release built here compiles consistently with what CI tests.
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.20.0-erlang-28.3.2-debian-bookworm-20260610-slim
#
ARG ELIXIR_VERSION=1.20.0
ARG OTP_VERSION=28.3.2
ARG DEBIAN_VERSION=bookworm-20260610-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies.
#
# No Node.js. The asset pipeline is the esbuild hex package alone, which fetches
# its own standalone binary, and there is no package.json, so nothing here runs
# node or npm (see the `assets.deploy` alias in mix.exs). The step that installed
# Node through the NodeSource script also failed every build: Docker runs RUN
# under /bin/sh (dash on Debian), which rejects the bash-only `set -o pipefail`
# with exit 2 before curl ran.
RUN apt-get update -y && apt-get install --no-install-recommends -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# Runtime libs (bookworm package names: libncurses6, not the bullseye
# libncurses5). The backup (Taina.Nhaman.Backup) is a plain SQLite snapshot
# with Exqlite, so no database client is needed here.
RUN apt-get update -y && \
  apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Create the writable data directories (the SQLite database, Ybira file
# storage, Nhaman backups). All are mounted over by named volumes in
# docker-compose. Docker seeds an empty named volume with the image's contents
# and ownership, so creating them here with the runtime user's ownership is
# what makes them writable once mounted. Missing /app/backups means the volume
# mounts root-owned and the nobody user cannot write a backup (Nhaman logs
# "Backup falhou" and moves on).
RUN mkdir -p /app/data /app/storage /app/backups \
    && chown nobody:nogroup /app/data /app/storage /app/backups

# Set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/taina ./

USER nobody
# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENV TINI_VERSION v0.19.0
# ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
# RUN chmod +x /tini
# ENTRYPOINT ["/tini", "--"]

CMD ["sh", "-c", "/app/bin/taina eval 'Taina.Release.migrate' && exec /app/bin/server"]
