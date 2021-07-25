FROM elixir:1.12.2-slim

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apt-get update
RUN apt-get install -y git curl bash libgcc1

COPY . /app

RUN mix deps.get
RUN MIX_ENV=prod COOKIE=fake mix compile --warnings-as-errors

CMD bash docker-entrypoint.sh
