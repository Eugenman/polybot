FROM elixir:1.18.2-otp-27

RUN apt-get update && apt-get install -y \
  build-essential \
  git \
  nodejs \
  npm \
  postgresql-client \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN MIX_ENV=prod mix deps.get --only prod

COPY config config/
RUN MIX_ENV=prod mix deps.compile

COPY assets assets/
COPY priv priv/
COPY lib lib/

RUN MIX_ENV=prod mix assets.deploy
RUN MIX_ENV=prod mix compile

CMD ["sh", "-c", "mix ecto.migrate && mix phx.server"]
