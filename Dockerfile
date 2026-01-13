FROM elixir:1.15-alpine AS builder
RUN apk add --no-cache build-base git
WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
RUN mix compile && mix release

FROM alpine:3.18 AS runner
RUN apk add --no-cache libstdc++ openssl ncurses-libs
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/message_service ./
ENV PHX_SERVER=true MIX_ENV=prod
EXPOSE 4003
CMD ["bin/message_service", "start"]
