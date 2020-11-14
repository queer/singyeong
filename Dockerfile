FROM elixir:1.11.2

RUN apt-get update && apt-get install -y build-essential

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apt-get update
RUN apt-get install -y git curl bash libgcc1

COPY . /app

RUN mix deps.get
RUN MIX_ENV=prod mix compile --warnings-as-errors

CMD bash docker-entrypoint.sh
