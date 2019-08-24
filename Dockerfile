FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git curl bash

COPY . /app

RUN mix deps.get
RUN MIX_ENV=test mix coveralls.json
RUN curl -sSL "https://codecov.io/bash" | bash
RUN MIX_ENV=prod mix compile

CMD epmd -daemon && MIX_ENV=prod mix phx.server
