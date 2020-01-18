FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git curl bash libgcc

COPY . /app

RUN mix deps.get
RUN mix test
RUN MIX_ENV=prod mix compile

CMD bash docker-entrypoint.sh
