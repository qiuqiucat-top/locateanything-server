# AGENTS.md — locateanything-server

This document is for both humans and AI agents who need to maintain or
reproduce the `locateanything-server:cuda` Docker image.

## What this image is

`locateanything-server` is a one-line patch over
[`ghcr.io/ggml-org/llama.cpp:server-cuda`](https://github.com/ggml-org/llama.cpp):

```
stock llama.cpp:server-cuda     +     our fork-built llama-server
                                           (yuuko-eth/llama.cpp @ mtmd-grounders)
                                           ↓
                                  llama.cpp-grounders:server-cuda
                                           ↓
                                  locateanything-server:cuda (this repo)
```

### Why it exists

The official `llama.cpp` does not know how to load the `LocateAnything-3B`
vision projector (`PROJECTOR_TYPE_LOCATEANYTHING`). When you point the stock
`llama-server` at a `mmproj-LocateAnything-3B-BF16.gguf`, you get:

```
E clip_init: failed to load model 'mmproj-LocateAnything-3B-BF16.gguf':
  load_hparams: unknown projector type: locateanything
```

The fix lives on a personal fork that adds the LocateAnything integration:
**`https://github.com/yuuko-eth/llama.cpp/tree/mtmd-grounders`**.

This repo builds that fork and substitutes its `llama-server` binary into
the stock image. Everything else (CLI surface, OpenAI-compatible API, KV
cache, batching, …) is identical to stock.

## Repository layout

```
locateanything-server/
├── Dockerfile                       # multi-stage, BUILD_MODE=bundle|source
├── llama-server.tar.gz              # prebuilt binary (36 MB, gzip-compressed)
├── README.md                        # quickstart
├── AGENTS.md                        # this file
├── scripts/
│   ├── build.sh                     # one-shot docker build helper
│   └── verify.sh                    # smoke test against /v1/models and a tiny request
├── examples/
│   ├── docker-compose.yaml          # standalone run, single GPU
│   └── request.json                 # minimal OpenAI-compatible payload
└── .dockerignore
```

## Two build modes

| `BUILD_MODE` | When to use | Trade-offs |
|---|---|---|
| `bundle` (default) | You trust the bundled `llama-server.tar.gz` | Reproducible byte-for-byte, fastest (~30 s on warm Docker cache). Works on any host that can pull stock `ghcr.io/ggml-org/llama.cpp:server-cuda`. |
| `source` | The bundled binary is for a different CUDA arch / driver, or you want a fully-audited build chain. | Slow (~10–20 min), requires the build host to fetch the fork and compile. |

Switch modes:

```bash
# default (fast, uses bundled binary)
docker build -t locateanything-server:cuda .

# full source rebuild
docker build --build-arg BUILD_MODE=source -t locateanything-server:cuda .
```

The bundled binary was built against:

* `nvidia/cuda:12.2.91`
* sm_86 (RTX 3090 / RTX 3080 / A40 / …); built `-DGGML_CUDA=ON` only
* `cmake 4.4.3`, `gcc 10.5.0`, `-O3 -march=native`
* `LLAMA_BUILD_TESTS=OFF`, `LLAMA_BUILD_EXAMPLES=OFF`
* upstream tag: `0.4.0-dev` (commit `8c19216`, ggml `0.23.0`)

It is functionally identical to a source-mode build from the same fork at
the same commit; the only thing you lose by trusting it is the ability to
audit every `.o` file.

## Required runtime flags

The model relies on three flags that stock setups often forget:

| Flag | Why |
|---|---|
| `--special` | Emits the special tokens `<ref>`, `<box>`, `<0>..<999>`, `<|im_end|>` instead of stripping them. Without it, the output has no coordinates. |
| `--mmproj /models/mmproj-LocateAnything-3B-BF16.gguf` | The vision projector. Must be BF16 — there is no quantised variant. |
| `-m /models/LocateAnything-3B-Q4_K_M.gguf` (or BF16) | The language-model weights. Q4_K_M is the recommended quantisation (2.1 GB, ~no accuracy loss vs BF16). |

See `examples/docker-compose.yaml` for the full set we ship with.

## How the bundled binary is reproduced

From a clean checkout of this repo, on a host with CUDA 12.x and a working
NVIDIA driver:

```bash
git clone --branch mtmd-grounders --depth 1 \
    https://github.com/yuuko-eth/llama.cpp.git /tmp/llama-fork
cd /tmp/llama-fork
cmake -B build \
    -DGGML_CUDA=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j"$(nproc)" --target llama-server
sha256sum build/bin/llama-server
tar czf llama-server.tar.gz -C build/bin llama-server
```

The SHA-256 of the *archive* published in this repo must match what your
build produced. If it doesn't, something in the fork has changed and you
should either re-bundle or build with `BUILD_MODE=source`.

## Why a Docker image and not a bare binary?

* The image carries the CUDA runtime, cuBLAS, etc. baked in, so the host
  only needs the NVIDIA driver (and a matching container toolkit).
* The stock `ghcr.io/ggml-org/llama.cpp:server-cuda` image already layers
  on top of CUDA and exposes `/app/llama-server`; replacing that one file
  is the smallest possible diff and inherits every upstream fix.
* It gives you a stable, publishable name (`locateanything-server:cuda`)
  that hides the fork dependency.

## Publishing to a registry

This server cannot reach `registry-1.docker.io`, so we publish via GitHub
instead:

1. Create a GitHub repo named `locateanything-server` under your account.
2. `git remote add origin git@github.com:YOURNAME/locateanything-server.git`
3. `git push -u origin main`

This repo is published at `https://github.com/qiuqiucat-top/locateanything-server`.

If you also want to ship the Docker image, see the workflow below.

### Publishing the Docker image without `docker push` to Docker Hub

When the build host cannot reach Docker Hub, you have two options:

**Option A — export / transfer / load:**

```bash
# on this build host
docker save locateanything-server:cuda | gzip > locateanything-server-cuda.tar.gz

# on any machine with Docker Hub access
docker load < locateanything-server-cuda.tar.gz
docker tag  locateanything-server:cuda YOURNAME/locateanything-server:cuda
docker push YOURNAME/locateanything-server:cuda
```

**Option B — use GitHub Container Registry (`ghcr.io`) instead of Docker Hub:**

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOURNAME --password-stdin
docker tag  locateanything-server:cuda ghcr.io/YOURNAME/locateanything-server:cuda
docker push ghcr.io/YOURNAME/locateanything-server:cuda
```

The image is ~4.6 GB; push time on a typical link is ~5–10 minutes.

## Smoke test (verifies grounding output, not just load)

After the container is running on port 8080:

```bash
./scripts/verify.sh http://127.0.0.1:8080
```

Expected line in the assistant output:

```
<ref>car</ref><box><123><456><789><012></box>...<|im_end|>
```

The presence of `<ref>`, `<box>`, and `<|im_end|>` proves that
`--special` and the patched projector type are both wired correctly.

## Compatibility matrix

| GPU | sm | bundled binary | `BUILD_MODE=source` |
|---|---|---|---|
| RTX 3090 / 3080 | 86 | ✅ built for this | ✅ |
| RTX 4090 / 4080 | 89 | ✅ runs (forward-compat) | ✅ |
| A100 | 80 | ✅ runs (forward-compat) | ✅ |
| V100 | 70 | ⚠️ may need source build with `-DGGML_CUDA_ARCHITECTURES=70` | ✅ |
| Anything older than sm_50 | — | ❌ unsupported by upstream | ❌ |

The bundled binary was compiled with `CMAKE_CUDA_ARCHITECTURES=86-real`;
CUDA's PTX forward-compatibility lets it JIT-compile for newer arches at
first launch. Older arches need a source rebuild.

## License

The binary is built from a fork of `llama.cpp`, which is MIT-licensed.
LocateAnything-3B model weights are governed by NVIDIA's release terms —
see the upstream repo.