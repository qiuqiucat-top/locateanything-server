# locateanything-server

[English](README.md) | [中文](README.zh-CN.md)

A Docker image that runs the **LocateAnything-3B** vision-language model
through an OpenAI-compatible HTTP server. Drop-in replacement for stock
`llama-server` for the LocateAnything GGUF.

---

## 📦 Pulling the image / 拉取镜像

The image is published to **GitHub Container Registry** (`ghcr.io`) under
the namespace `qiuqiucat-top`. Tags follow semantic versioning with
always-on aliases:

| Tag | When | Example |
|---|---|---|
| `:cuda` | every push to `main` | `ghcr.io/qiuqiucat-top/locateanything-server:cuda` |
| `:latest` | every push to `main` | `ghcr.io/qiuqiucat-top/locateanything-server:latest` |
| `:<version>` (e.g. `:1.2.3`) | every `git tag v*` push | `ghcr.io/qiuqiucat-top/locateanything-server:1.2.3` |
| `:<major>` / `:<major>.<minor>` | same | `:1`, `:1.2` |

### Pull

```bash
# latest build on main
docker pull ghcr.io/qiuqiucat-top/locateanything-server:cuda

# or pin to a specific version (after a git tag has been pushed)
docker pull ghcr.io/qiuqiucat-top/locateanything-server:1.0.0
```

### Verify the pull

```bash
# Should print llama.cpp version banner and exit 0
docker run --rm --gpus all \
  ghcr.io/qiuqiucat-top/locateanything-server:cuda \
  --version
```

If you see `pull access denied`, the image is private in your account —
see [Making the package public](#making-the-package-public) below.

### Authenticated pulls (private forks)

If you forked this repo, the Actions-built image lives under **your**
namespace and is private by default. To pull it:

```bash
echo "$GITHUB_PAT" | docker login ghcr.io -u YOURNAME --password-stdin
docker pull ghcr.io/YOURNAME/locateanything-server:cuda
```

The PAT needs `read:packages` scope.

### Making the package public

For this public repo (`qiuqiucat-top/locateanything-server`), the image
is public. If you fork and want yours public too:

1. Push to GitHub, let Actions build the image once.
2. Go to `https://github.com/YOURNAME?tab=packages` and click the package.
3. **Package settings → Danger Zone → Change package visibility → Public**.

---

## 🖥️ NVIDIA driver support / 显卡驱动支持

The image embeds the **CUDA 12.8 runtime** (carried in by the stock
`ghcr.io/ggml-org/llama.cpp:server-cuda` base image). The bundled
`llama-server` binary was compiled with CUDA 12.2 but dynamically links
only against the forward-compatible runtime API, so the host driver
requirement is determined by CUDA 12.8, **not** by 12.2.

### Minimum supported driver

| OS | Architecture | Minimum driver | Tested |
|---|---|---|---|
| **Linux** | x86_64 | **≥ 570.86.16** | 580.95.05 (RTX 3090) |
| **Windows** | x86_64 | **≥ 570.86.16** | _not tested_ |
| **Linux** | ARM64 (aarch64) | **≥ 570.86.16** | _not tested_ |
| **Linux** | x86_64 (Pascal / SM 6.x) | **≥ 570.86.16** but may need a self-rebuild — see "Older GPUs" below | — |

Check your current driver:

```bash
nvidia-smi --query-gpu=driver_version,name --format=csv
# driver_version
# 580.95.05
# NVIDIA GeForce RTX 3090
```

### Recommended drivers

| Driver branch | CUDA compatibility | Notes |
|---|---|---|
| **580.x** (latest stable) | 13.0 / 12.8 / 12.6 / 12.4 | ✅ recommended |
| **575.x** (LTS) | 12.8 / 12.6 / 12.4 | ✅ good |
| **570.x** | 12.8 / 12.6 / 12.4 | ⚠️ minimum, missing some 12.8 features |
| **≤ 555.x** | 12.5 / 12.4 | ❌ image will fail to start: `cuda runtime error: no CUDA-capable device is detected` or similar |

### Installing / upgrading

**Linux (Ubuntu / Debian)**

```bash
# Method 1: distro package manager (Ubuntu 22.04+)
sudo apt-get update && sudo apt-get install -y nvidia-driver-580

# Method 2: NVIDIA's official .run installer (any distro)
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.95.05/NVIDIA-Linux-x86_64-580.95.05.run
sudo sh NVIDIA-Linux-x86_64-580.95.05.run

# Reboot after install
sudo reboot

# Verify
nvidia-smi
```

**Windows**

Download the **580.x Studio Driver** (or Game Ready Driver) from
<https://www.nvidia.com/drivers>. Reboot. Run `nvidia-smi` in a PowerShell
window to confirm.

### Docker / NVIDIA Container Toolkit

In addition to the host driver, you also need the **NVIDIA Container
Toolkit** so Docker can pass the GPU through.

```bash
# Linux only — Windows uses Docker Desktop's built-in WSL2 GPU passthrough.
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify:

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
# Should print your GPU(s) — same as the host's `nvidia-smi` output.
```

### Older GPUs (compute capability < 7.0)

The prebuilt binary is compiled for **sm_86** (RTX 3090 / 3080 / A40).
CUDA's PTX forward-compatibility will JIT-compile it for newer arches
(RTX 4090, H100, …) at first launch, so anything from sm_70 (V100) up
to the latest works **out of the box**.

For GPUs **older than sm_50** (Kepler and earlier), `llama.cpp` doesn't
support them at all — there is no software fix.

For GPUs in the **sm_50–sm_60** range (Maxwell / Pascal), the binary may
work via JIT but is untested. To be safe, rebuild from source against
your exact arch:

```bash
git clone --branch mtmd-grounders --depth 1 \
    https://github.com/yuuko-eth/llama.cpp.git llama-fork
cd llama-fork
cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="60-real"   # <-- your arch here
cmake --build build --config Release -j$(nproc) --target llama-server
# Then replace /app/llama-server in the running image:
docker run --rm -v $(pwd)/build/bin:/out \
  ghcr.io/qiuqiucat-top/locateanything-server:cuda \
  cp /app/llama-server /out/llama-server.original
cp build/bin/llama-server llama-server.rebuilt
```

`AGENTS.md` documents the full source rebuild path.

---

## ▶️ Run

After pulling and confirming the driver:

```bash
docker run --rm --gpus all \
  -v /path/to/models:/models:ro \
  -p 8080:8080 \
  ghcr.io/qiuqiucat-top/locateanything-server:cuda \
  -m /models/LocateAnything-3B-Q4_K_M.gguf \
  --mmproj /models/mmproj-LocateAnything-3B-BF16.gguf \
  --special \
  --host 0.0.0.0 --port 8080 \
  --jinja -ngl 99 --main-gpu 0 --mmproj-device CUDA0
```

Then send a request:

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @examples/request.json
```

The assistant will return lines like:

```xml
<ref>car</ref><box><123><456><789><012></box><|im_end|>
```

Coordinates are normalised to a 0–1000 grid; multiply by image
width/height to convert to pixels.

---

## 🗂 What you need on disk

```
LocateAnything-3B-Q4_K_M.gguf        # 2.1 GB — language-model weights
mmproj-LocateAnything-3B-BF16.gguf   # 0.87 GB — vision projector (BF16 only)
```

The BF16 (7.3 GB) variant of the LLM also works; Q4_K_M is recommended
for production.

---

## 🧱 Compose / 多容器协同

See `examples/docker-compose.yaml` for a one-service Compose file that
binds a single GPU and exposes 8080.

---

## 🔧 Building from source instead of using the prebuilt bundle

The image ships a prebuilt `llama-server.tar.gz` (~36 MB) baked into the
repo. If you need a different CUDA arch / driver / fork revision:

```bash
# 1. Build the binary on a CUDA-capable host
git clone --branch mtmd-grounders --depth 1 \
    https://github.com/yuuko-eth/llama.cpp.git /tmp/llama-fork
cd /tmp/llama-fork
cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_ARCHITECTURES=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d ' ') \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc) --target llama-server

# 2. Replace the bundled archive with your build
cd /path/to/locateanything-server
tar czf llama-server.tar.gz -C /tmp/llama-fork/build/bin llama-server
NEW_SHA=$(sha256sum llama-server.tar.gz | cut -d' ' -f1)
sed -i "s/^ARG BUNDLED_BINARY_SHA256=.*/ARG BUNDLED_BINARY_SHA256=$NEW_SHA/" Dockerfile

# 3. Build the image as usual
docker build -t locateanything-server:cuda .
```

## 📖 See also

- [中文文档 (Chinese)](README.zh-CN.md)
- [`AGENTS.md`](AGENTS.md) — full maintainer guide: build reproduction,
  registry publishing, compatibility matrix, troubleshooting.
- [`examples/docker-compose.yaml`](examples/docker-compose.yaml) — Compose template.
- [`examples/request.json`](examples/request.json) — minimal API payload.
- [`scripts/build.sh`](scripts/build.sh) — one-shot build helper.
- [`scripts/verify.sh`](scripts/verify.sh) — health + grounding smoke test.

---

## 📝 License

The bundled binary inherits the MIT license of upstream `llama.cpp`. The
LocateAnything-3B model weights are subject to NVIDIA's release terms.