FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git curl bash gcc libc-dev

COPY . /app

RUN mix deps.get
RUN mix test
RUN MIX_ENV=prod mix compile

RUN apk del gcc libc-dev

CMD bash docker-entrypoint.sh
