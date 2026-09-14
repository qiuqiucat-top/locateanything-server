# locateanything-server

[English](README.md) | [中文](README.zh-CN.md)

一个用于跑 **LocateAnything-3B** 视觉-语言模型的 Docker 镜像，通过
OpenAI 兼容的 HTTP server 提供推理。可以直接当作 stock `llama-server`
的替代品来加载 LocateAnything GGUF。

---

## 📦 拉取镜像

镜像发布在 **GitHub Container Registry** (`ghcr.io`)，命名空间是
`qiuqiucat-top`。标签遵循语义化版本 + 始终存在的别名：

| 标签 | 何时打 | 示例 |
|---|---|---|
| `:cuda` | 每次 push 到 `main` | `ghcr.io/qiuqiucat-top/locateanything-server:cuda` |
| `:latest` | 每次 push 到 `main` | `ghcr.io/qiuqiucat-top/locateanything-server:latest` |
| `:<version>` (例如 `:1.2.3`) | 每次 `git tag v*` push | `ghcr.io/qiuqiucat-top/locateanything-server:1.2.3` |
| `:<major>` / `:<major>.<minor>` | 同上 | `:1`, `:1.2` |

### 拉取命令

```bash
# main 分支最新构建
docker pull ghcr.io/qiuqiucat-top/locateanything-server:cuda

# 或锁定到具体版本（要先 git tag push 过）
docker pull ghcr.io/qiuqiucat-top/locateanything-server:1.0.0
```

### 验证拉取

```bash
# 应该打印 llama.cpp 版本信息并以 0 退出
docker run --rm --gpus all \
  ghcr.io/qiuqiucat-top/locateanything-server:cuda \
  --version
```

如果出现 `pull access denied`，说明镜像在你的账号下还是私有的——
参考下面的 [如何把镜像设为公开](#如何把镜像设为公开)。

### 鉴权拉取（私有 fork）

如果你是 fork 了这个 repo，Actions 编译出来的镜像默认放在 **你的**
namespace 下且是私有的。要拉取需要：

```bash
echo "$GITHUB_PAT" | docker login ghcr.io -u 你的用户名 --password-stdin
docker pull ghcr.io/你的用户名/locateanything-server:cuda
```

PAT 需要 `read:packages` 权限。

### 如何把镜像设为公开

本仓库（`qiuqiucat-top/locateanything-server`）的镜像是公开的。
如果你 fork 后也想设成公开：

1. 推到 GitHub，让 Actions 构建一次镜像。
2. 进入 `https://github.com/你的用户名?tab=packages`，点击对应 package。
3. **Package settings → Danger Zone → Change package visibility → Public**。

---

## 🖥️ 显卡驱动支持

镜像内嵌了 **CUDA 12.8 runtime**（从 stock `ghcr.io/ggml-org/llama.cpp:server-cuda`
基础镜像继承）。我们打的 `llama-server` 二进制是用 CUDA 12.2 编译的，
但运行时只链接了向前兼容的 API，所以驱动版本要求由 **CUDA 12.8**
决定，跟 12.2 无关。

### 最低支持的驱动版本

| 系统 | 架构 | 最低驱动 | 测试过的版本 |
|---|---|---|---|
| **Linux** | x86_64 | **≥ 570.86.16** | 580.95.05（RTX 3090）|
| **Windows** | x86_64 | **≥ 570.86.16** | 未测试 |
| **Linux** | ARM64（aarch64）| **≥ 570.86.16** | 未测试 |
| **Linux** | x86_64 老架构（Pascal / SM 6.x）| **≥ 570.86.16**，但可能需要自行 rebuild——见下文「老显卡」 | — |

查看当前驱动版本：

```bash
nvidia-smi --query-gpu=driver_version,name --format=csv
# driver_version
# 580.95.05
# NVIDIA GeForce RTX 3090
```

### 推荐的驱动分支

| 驱动分支 | CUDA 兼容性 | 说明 |
|---|---|---|
| **580.x**（最新稳定）| 13.0 / 12.8 / 12.6 / 12.4 | ✅ 推荐 |
| **575.x**（LTS）| 12.8 / 12.6 / 12.4 | ✅ 推荐 |
| **570.x** | 12.8 / 12.6 / 12.4 | ⚠️ 最低要求，少部分 12.8 特性缺失 |
| **≤ 555.x** | 12.5 / 12.4 | ❌ 镜像启动会失败：`cuda runtime error: no CUDA-capable device is detected` 等 |

### 安装 / 升级驱动

**Linux（Ubuntu / Debian）**

```bash
# 方式 1：用发行版包管理器（Ubuntu 22.04+）
sudo apt-get update && sudo apt-get install -y nvidia-driver-580

# 方式 2：NVIDIA 官方的 .run 安装器（任意发行版）
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.95.05/NVIDIA-Linux-x86_64-580.95.05.run
sudo sh NVIDIA-Linux-x86_64-580.95.05.run

# 安装完重启
sudo reboot

# 验证
nvidia-smi
```

**Windows**

从 <https://www.nvidia.com/drivers> 下载 **580.x Studio Driver**（或
Game Ready Driver），重启。在 PowerShell 跑 `nvidia-smi` 确认。

### Docker / NVIDIA Container Toolkit

除了 host 上的驱动，还需要 **NVIDIA Container Toolkit** 让 Docker 把
GPU 透传给容器。

```bash
# 仅 Linux——Windows 用 Docker Desktop 自带的 WSL2 GPU passthrough
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

验证：

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
# 应该打印你的 GPU 信息——跟主机 `nvidia-smi` 一致
```

### 老显卡（compute capability < 7.0）

预编译的二进制是针对 **sm_86**（RTX 3090 / 3080 / A40）编译的。CUDA 的
PTX 向前兼容性会在首次启动时 JIT 编译到更新的架构（RTX 4090、H100、
…），所以从 sm_70（V100）开始到最新的卡都 **开箱即用**。

**比 sm_50 还老的卡**（Kepler 及更早），`llama.cpp` 根本不支持，
没有软件层面的解决方案。

**sm_50–sm_60 的卡**（Maxwell / Pascal），理论上 JIT 可以跑通但没测试
过。要稳妥使用，请针对你的架构从源码重新编译：

```bash
git clone --branch mtmd-grounders --depth 1 \
    https://github.com/yuuko-eth/llama.cpp.git llama-fork
cd llama-fork
cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="60-real"   # <-- 替换成你的架构
cmake --build build --config Release -j$(nproc) --target llama-server
# 然后替换运行镜像里的 /app/llama-server
docker run --rm -v $(pwd)/build/bin:/out \
  ghcr.io/qiuqiucat-top/locateanything-server:cuda \
  cp /app/llama-server /out/llama-server.original
cp build/bin/llama-server llama-server.rebuilt
```

完整的源码重建步骤见 [`AGENTS.md`](AGENTS.md)。

---

## ▶️ 运行

拉好镜像 + 确认驱动 OK 之后：

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

然后发请求：

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @examples/request.json
```

assistant 会返回类似：

```xml
<ref>car</ref><box><123><456><789><012></box><|im_end|>
```

坐标是 0–1000 归一化的，乘以图像宽高就能换算成像素。

---

## 🗂 需要的模型文件

```
LocateAnything-3B-Q4_K_M.gguf        # 2.1 GB — LLM 权重
mmproj-LocateAnything-3B-BF16.gguf   # 0.87 GB — 视觉投影器（必须 BF16）
```

LLM 也可以用 BF16（7.3 GB）版；生产环境推荐 Q4_K_M。

---

## 🧱 Compose / 多容器协同

单服务、绑单 GPU、暴露 8080 的 Compose 模板见 `examples/docker-compose.yaml`。

---

## 🔧 从源码编译（不用预编译 bundle）

镜像内置了一个 ~36 MB 的 `llama-server.tar.gz`。如果你的 CUDA 架构 / 驱动
/ fork 版本跟预编译不匹配：

```bash
# 1. 在有 CUDA 的机器上编译
git clone --branch mtmd-grounders --depth 1 \
    https://github.com/yuuko-eth/llama.cpp.git /tmp/llama-fork
cd /tmp/llama-fork
cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_ARCHITECTURES=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d ' ') \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc) --target llama-server

# 2. 替换仓库里的 bundle
cd /path/to/locateanything-server
tar czf llama-server.tar.gz -C /tmp/llama-fork/build/bin llama-server
NEW_SHA=$(sha256sum llama-server.tar.gz | cut -d' ' -f1)
sed -i "s/^ARG BUNDLED_BINARY_SHA256=.*/ARG BUNDLED_BINARY_SHA256=$NEW_SHA/" Dockerfile

# 3. 正常 build 镜像
docker build -t locateanything-server:cuda .
```

## 📖 相关链接

- [English documentation](README.md)
- [`AGENTS.md`](AGENTS.md) — 维护者指南：构建复现、registry 发布、兼容
  性矩阵、故障排查。
- [`examples/docker-compose.yaml`](examples/docker-compose.yaml) — Compose 模板。
- [`examples/request.json`](examples/request.json) — 最小 API payload。
- [`scripts/build.sh`](scripts/build.sh) — 一键构建脚本。
- [`scripts/verify.sh`](scripts/verify.sh) — 健康检查 + grounding 冒烟测试。

---

## 📝 协议

内嵌的二进制继承上游 `llama.cpp` 的 MIT 协议。LocateAnything-3B 模型
权重遵循 NVIDIA 的发布条款。