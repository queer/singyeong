FROM elixir:1.10.4-slim

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apt-get update
RUN apt-get install -y git curl bash libgcc1

COPY . /app

RUN mix deps.get
RUN MIX_ENV=test mix compile --warnings-as-errors
RUN MIX_ENV=test mix test
RUN MIX_ENV=prod mix compile --warnings-as-errors

CMD bash docker-entrypoint.sh
