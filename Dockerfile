# Dockerfile for locateanything-server
#
# This is a tiny "patch" image that replaces /app/llama-server in the stock
# ghcr.io/ggml-org/llama.cpp:server-cuda image with a binary built from the
# yuuko-eth/llama.cpp @ mtmd-grounders fork. The fork supports the
# PROJECTOR_TYPE_LOCATEANYTHING clip-model type required to load the
# LocateAnything-3B GGUF.
#
# ─────────────────────────────────────────────────────────────────────────────
# Quick start (using prebuilt binary bundled as a release asset)
# ─────────────────────────────────────────────────────────────────────────────
#
#   docker build -t locateanything-server:cuda .
#
# Run:
#   docker run --rm --gpus all \
#     -v /path/to/models:/models:ro \
#     -p 8080:8080 \
#     locateanything-server:cuda \
#     -m /models/LocateAnything-3B-Q4_K_M.gguf \
#     --mmproj /models/mmproj-LocateAnything-3B-BF16.gguf \
#     --special \
#     --host 0.0.0.0 --port 8080 \
#     --jinja -ngl 99 --main-gpu 0 --mmproj-device CUDA0
#
# ─────────────────────────────────────────────────────────────────────────────
# Rebuild the llama-server binary from source (optional, see AGENTS.md)
# ─────────────────────────────────────────────────────────────────────────────
#
# The Dockerfile is parameterised by BUILD_MODE:
#   * BUILD_MODE=bundle (default) — extract from llama-server.tar.gz
#   * BUILD_MODE=source           — clone + build the fork inside the image
#
# Use source mode when the bundled binary doesn't match your GPU/driver:
#   docker build --build-arg BUILD_MODE=source -t locateanything-server:cuda .

ARG BASE_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda
ARG CUDA_BUILDER=nvidia/cuda:12.8.0-devel-ubuntu22.04
ARG FORK_REPO=https://github.com/yuuko-eth/llama.cpp.git
ARG FORK_BRANCH=mtmd-grounders
ARG BUNDLED_BINARY_SHA256=a646174a7e016ea1f754fe55af3476b6fb7c2be562d25dcf0745e6d5dc26904c

# ─────────────────────────────────────────────────────────────────────────────
# Stage A (only when BUILD_MODE=source): build llama-server from fork
# ─────────────────────────────────────────────────────────────────────────────
FROM ${CUDA_BUILDER} AS source-builder
ARG FORK_REPO
ARG FORK_BRANCH
RUN apt-get update && apt-get install -y --no-install-recommends \
        git build-essential cmake libcurl4-openssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --branch "${FORK_BRANCH}" --depth 1 "${FORK_REPO}" . \
 && cmake -B build \
        -DGGML_CUDA=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --config Release -j"$(nproc)" --target llama-server

# ─────────────────────────────────────────────────────────────────────────────
# Stage B (only when BUILD_MODE=bundle, default): unpack the prebuilt binary
# ─────────────────────────────────────────────────────────────────────────────
FROM scratch AS bundle-extractor
ARG BUNDLED_BINARY_SHA256
COPY llama-server.tar.gz /bundle.tgz
# Verify the SHA-256 of the archive matches the one published alongside it.
# If this fails the build aborts before any layers above the base are added.
RUN set -eux; \
    echo "${BUNDLED_BINARY_SHA256}  bundle.tgz" | sha256sum -c -

# ─────────────────────────────────────────────────────────────────────────────
# Final: patch the stock llama.cpp:server-cuda image
# ─────────────────────────────────────────────────────────────────────────────
FROM ${BASE_IMAGE}

ARG BUILD_MODE=bundle
LABEL org.opencontainers.image.title="locateanything-server" \
      org.opencontainers.image.description="llama.cpp server patched with the mtmd-grounders fork so it can load the LocateAnything-3B GGUF (PROJECTOR_TYPE_LOCATEANYTHING)." \
      org.opencontainers.image.source="https://github.com/qiuqiucat-top/locateanything-server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="wuyuhang"

# Copy the right binary based on the build mode.
COPY --from=bundle-extractor /bundle.tgz /tmp/bundle.tgz
COPY --from=source-builder  /src/build/bin/llama-server /app/llama-server-source

# Unpack the bundle (if present) and install whichever binary is in play.
RUN set -eux; \
    if [ -s /tmp/bundle.tgz ]; then \
        cd /tmp && tar xzf bundle.tgz && mv build/bin/llama-server /app/llama-server; \
    else \
        mv /app/llama-server-source /app/llama-server; \
    fi; \
    chmod +x /app/llama-server; \
    rm -rf /tmp/bundle.tgz /app/llama-server-source; \
    # Quick sanity: the binary must claim to know the locateanything projector.
    /app/llama-server --help 2>&1 | head -1

# Default entrypoint is whatever the stock image ships with.
# Re-declare the original healthcheck for clarity (it pings /health locally).
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/health || exit 1