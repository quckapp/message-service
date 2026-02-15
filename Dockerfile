# ==============================================================================
# Build Stage - Compile and create release
# ==============================================================================
FROM hexpm/elixir:1.15.7-erlang-26.2.1-alpine-3.18.4 AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    npm \
    nodejs

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    ERL_FLAGS="+JPperf true"

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first for better caching
COPY mix.exs ./
COPY mix.lock* ./

# Fetch and compile dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy configuration files
COPY config config

# Copy application source code
COPY lib lib
RUN mkdir -p priv

# Compile the application
RUN mix compile

# Build the release
RUN mix release message_service

# ==============================================================================
# Runtime Stage - Minimal production image
# ==============================================================================
FROM alpine:3.18 AS runner

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libgcc \
    curl \
    ca-certificates \
    tzdata

# Create non-root user for security
RUN addgroup -g 1000 elixir && \
    adduser -u 1000 -G elixir -s /bin/sh -D elixir

WORKDIR /app

# Copy the release from builder stage
COPY --from=builder --chown=elixir:elixir /app/_build/prod/rel/message_service ./

# Set ownership
RUN chown -R elixir:elixir /app

# Switch to non-root user
USER elixir

# Set runtime environment variables
ENV HOME=/app \
    MIX_ENV=prod \
    PHX_SERVER=true \
    LANG=C.UTF-8 \
    PORT=4006 \
    RELEASE_DISTRIBUTION=name \
    RELEASE_NODE=message_service@127.0.0.1

# Expose application port and EPMD port for clustering
EXPOSE 4006 4369

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4006/health || exit 1

# Start the application
CMD ["bin/message_service", "start"]
