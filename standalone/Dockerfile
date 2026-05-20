# syntax=docker/dockerfile:1
# Self-hosted CompletionKit — the bundled standalone app.
#
# The build context MUST be the repository root: the standalone app depends on
# the engine gem through a relative path (`gem "completion-kit", path: "../"`),
# so the engine source has to be in the context too.
#
#   docker build -f standalone/Dockerfile -t completion-kit .
#
# Run it (web + worker are two containers off the same image):
#
#   docker run -d --name completion-kit-web -p 3000:3000 \
#     -e DATABASE_URL=postgres://user:pass@host/db \
#     -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
#     -e COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY=... \
#     -e COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY=... \
#     -e COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT=... \
#     completion-kit
#
#   docker run -d --name completion-kit-worker \
#     -e DATABASE_URL=... (+ the same SECRET_KEY_BASE and encryption keys) \
#     completion-kit ./bin/jobs

ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /completion-kit/standalone

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq5 libsqlite3-0 && \
    rm -rf /var/lib/apt/lists/*

# ---- build stage ----------------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential libpq-dev libsqlite3-dev libyaml-dev pkg-config git && \
    rm -rf /var/lib/apt/lists/*

# the engine gem — only the paths its gemspec actually packages
COPY completion-kit.gemspec Rakefile LICENSE README.md /completion-kit/
COPY app    /completion-kit/app
COPY config /completion-kit/config
COPY db     /completion-kit/db
COPY lib    /completion-kit/lib

# the standalone app
COPY standalone /completion-kit/standalone

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache && \
    bundle exec bootsnap precompile --gemfile

RUN bundle exec bootsnap precompile app/ lib/ 2>/dev/null || true

# a throwaway secret for asset compilation only — the real one is a runtime env
RUN SECRET_KEY_BASE=precompile_placeholder_secret_key_base_000000000000 \
    COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY=dummy \
    COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY=dummy \
    COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT=dummy \
    ./bin/rails assets:precompile

# ---- runtime stage --------------------------------------------------------
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /completion-kit /completion-kit

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /completion-kit
USER 1000:1000

ENTRYPOINT ["bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
