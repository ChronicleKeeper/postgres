# syntax=docker/dockerfile:1.7
# check=error=true

ARG POSTGRES_IMAGE=postgres:17.10@sha256:7958605b474b3d264a969cb3a123d6aa00ad1e1fe9da8a69984dabb704d93317
ARG POSTGRES_VERSION=17.10
ARG POSTGRES_MAJOR=17
ARG PGVECTOR_VERSION=0.8.2
ARG PGVECTOR_SHA256=69f4019389af05dc1c9548deb8628e62878e6e207c03907f2b8af2016472cdaa
ARG PG_TEXTSEARCH_VERSION=1.0.0
ARG PG_TEXTSEARCH_SHA256=c12f1d70c321177665ea3eb2cb8e42343abd9d1ff8a176a177419231cb5257ab

FROM ${POSTGRES_IMAGE} AS extensions

ARG POSTGRES_MAJOR
ARG PGVECTOR_VERSION
ARG PGVECTOR_SHA256
ARG PG_TEXTSEARCH_VERSION
ARG PG_TEXTSEARCH_SHA256

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Build-only packages follow the pinned PostgreSQL base's package repository.
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        "postgresql-server-dev-${POSTGRES_MAJOR}"

WORKDIR /usr/src

# Disable pgvector's -march=native default so the image remains CPU-portable.
RUN curl --fail --location --show-error --silent \
        "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz" \
        --output pgvector.tar.gz \
    && echo "${PGVECTOR_SHA256}  pgvector.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file pgvector.tar.gz \
    && make --directory="pgvector-${PGVECTOR_VERSION}" --jobs="$(nproc)" OPTFLAGS="" \
    && make --directory="pgvector-${PGVECTOR_VERSION}" DESTDIR=/opt/extensions OPTFLAGS="" install \
    && install --directory /opt/extensions/usr/share/doc/pgvector \
    && install --mode=0444 "pgvector-${PGVECTOR_VERSION}/LICENSE" /opt/extensions/usr/share/doc/pgvector/LICENSE

RUN curl --fail --location --show-error --silent \
        "https://github.com/timescale/pg_textsearch/archive/refs/tags/v${PG_TEXTSEARCH_VERSION}.tar.gz" \
        --output pg_textsearch.tar.gz \
    && echo "${PG_TEXTSEARCH_SHA256}  pg_textsearch.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file pg_textsearch.tar.gz \
    && make --directory="pg_textsearch-${PG_TEXTSEARCH_VERSION}" --jobs="$(nproc)" \
    && make --directory="pg_textsearch-${PG_TEXTSEARCH_VERSION}" DESTDIR=/opt/extensions install \
    && install --directory /opt/extensions/usr/share/doc/pg_textsearch \
    && install --mode=0444 "pg_textsearch-${PG_TEXTSEARCH_VERSION}/LICENSE" /opt/extensions/usr/share/doc/pg_textsearch/LICENSE

FROM ${POSTGRES_IMAGE}

ARG POSTGRES_VERSION
ARG PGVECTOR_VERSION
ARG PG_TEXTSEARCH_VERSION

LABEL org.opencontainers.image.title="Chronicle Keeper PostgreSQL" \
      org.opencontainers.image.description="PostgreSQL with pgvector, pg_textsearch, and pg_trgm for Chronicle Keeper" \
      org.opencontainers.image.source="https://github.com/ChronicleKeeper/ChronicleKeeperPostgres" \
      org.opencontainers.image.vendor="Chronicle Keeper" \
      org.chroniclekeeper.postgresql.version="${POSTGRES_VERSION}" \
      org.chroniclekeeper.pgvector.version="${PGVECTOR_VERSION}" \
      org.chroniclekeeper.pg-textsearch.version="${PG_TEXTSEARCH_VERSION}"

COPY --from=extensions /opt/extensions/ /
COPY --chmod=0555 initdb/00-create-extensions.sh /docker-entrypoint-initdb.d/00-create-extensions.sh

CMD ["postgres", "-c", "shared_preload_libraries=pg_textsearch"]
