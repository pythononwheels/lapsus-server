# Multi-stage build for the LAPSUS coordinator (server-side only).
#
# Only lapsus_core + lapsus_coordinator are copied in, so the agent's Rust/WebRTC
# NIFs (ex_sctp/ex_webrtc) are never fetched or compiled here — the server doesn't
# need them. The provider agent runs natively on user machines, not here.

# ---- build stage ----
FROM elixir:1.18.2-otp-27 AS build

ENV MIX_ENV=prod

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

# Deps first (cached layer): umbrella root + only the needed apps' mix files.
COPY mix.exs mix.lock ./
COPY config config
COPY apps/lapsus_core/mix.exs apps/lapsus_core/mix.exs
COPY apps/lapsus_coordinator/mix.exs apps/lapsus_coordinator/mix.exs
RUN mix deps.get --only prod
RUN mix deps.compile

# Source for the two server apps, then build the release.
COPY apps/lapsus_core apps/lapsus_core
COPY apps/lapsus_coordinator apps/lapsus_coordinator
RUN mix compile
RUN mix release lapsus_coordinator

# ---- runtime stage ----
FROM debian:bookworm-slim AS app

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 ca-certificates locales curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

WORKDIR /app
RUN useradd -ms /bin/bash app && mkdir -p /data && chown app:app /data
COPY --from=build --chown=app:app /app/_build/prod/rel/lapsus_coordinator ./

USER app

# Ledger DB lives on a mounted volume; server is enabled in the release.
ENV DATABASE_PATH=/data/coordinator.db \
    PHX_SERVER=true \
    PORT=4000

EXPOSE 4000
CMD ["bin/lapsus_coordinator", "start"]
