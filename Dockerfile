FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git curl bash libstdc++ gcc g++

COPY . /app

RUN mix deps.clean --all
RUN mix deps.get
RUN mix test
RUN MIX_ENV=prod mix compile

RUN apk del gcc g++

CMD bash docker-entrypoint.sh
