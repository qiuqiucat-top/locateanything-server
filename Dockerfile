# Dockerfile for locateanything-server
#
# Tiny patch over stock ghcr.io/ggml-org/llama.cpp:server-cuda:
# we replace /app/llama-server with a binary built from the
# yuuko-eth/llama.cpp @ mtmd-grounders fork, which adds support for the
# PROJECTOR_TYPE_LOCATEANYTHING clip-model type that stock llama.cpp
# doesn't know how to load.
#
# Build (default — uses bundled prebuilt binary, ~30 s):
#   docker build -t locateanything-server:cuda .
#
# Or with the build script:
#   ./scripts/build.sh
#
# The bundled binary is at llama-server.tar.gz in this repo (36 MB).
# Its SHA-256 is hard-coded below and verified on every build, so a
# tampered or stale binary can't sneak in.
#
# Run:
#   docker run --rm --gpus all \
#     -v /path/to/models:/models:ro -p 8080:8080 \
#     locateanything-server:cuda \
#     -m /models/LocateAnything-3B-Q4_K_M.gguf \
#     --mmproj /models/mmproj-LocateAnything-3B-BF16.gguf \
#     --special --host 0.0.0.0 --port 8080 \
#     --jinja -ngl 99 --main-gpu 0 --mmproj-device CUDA0
#
# Rebuilding the llama-server binary from source instead of using the
# bundle is documented in AGENTS.md — it's a 15–25 min build and
# typically not needed.

ARG BASE_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda
ARG BUNDLED_BINARY_SHA256=fa582a3866e37e388365d656597dd2e02978cc291aeeaffdae43783f0ab9ca27

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: extract the bundled binary and verify its integrity.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:3.19 AS bundle-extractor
ARG BUNDLED_BINARY_SHA256
RUN apk add --no-cache coreutils
WORKDIR /bundle
COPY llama-server.tar.gz .
RUN echo "${BUNDLED_BINARY_SHA256}  llama-server.tar.gz" | sha256sum -c - \
 && tar xzf llama-server.tar.gz \
 && [ -s llama-server ] || { echo "binary missing after extract" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: patch stock llama.cpp:server-cuda with our binary.
# ─────────────────────────────────────────────────────────────────────────────
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="locateanything-server" \
      org.opencontainers.image.description="llama.cpp server patched with the mtmd-grounders fork so it can load the LocateAnything-3B GGUF (PROJECTOR_TYPE_LOCATEANYTHING)." \
      org.opencontainers.image.source="https://github.com/qiuqiucat-top/locateanything-server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="qiuqiucat-top"

COPY --from=bundle-extractor /bundle/llama-server /app/llama-server
RUN chmod +x /app/llama-server

# Stock image listens on 8080 by default with `--port 8080`; re-declare
# a sensible healthcheck for that convention.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/health || exit 1