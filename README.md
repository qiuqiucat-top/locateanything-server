# locateanything-server

A Docker image that runs the **LocateAnything-3B** vision-language model
through an OpenAI-compatible HTTP server. Drop-in replacement for stock
`llama-server` for the LocateAnything GGUF.

## What it does

Runs `llama-server` from the
[`yuuko-eth/llama.cpp @ mtmd-grounders`](https://github.com/yuuko-eth/llama.cpp/tree/mtmd-grounders)
fork, which adds the `PROJECTOR_TYPE_LOCATEANYTHING` clip-model type that
official `llama.cpp` does not yet ship with.

## Quick start

```bash
docker build -t locateanything-server:cuda .

docker run --rm --gpus all \
    -v /path/to/models:/models:ro \
    -p 8080:8080 \
    locateanything-server:cuda \
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

## What you need on disk

```
LocateAnything-3B-Q4_K_M.gguf        # 2.1 GB — language-model weights
mmproj-LocateAnything-3B-BF16.gguf   # 0.87 GB — vision projector (BF16 only)
```

The BF16 (7.3 GB) variant of the LLM also works; Q4_K_M is recommended
for production.

## Compose

See `examples/docker-compose.yaml` for a one-service Compose file.

## Building from source instead of using the bundled binary

```bash
docker build --build-arg BUILD_MODE=source -t locateanything-server:cuda .
```

Slower (~10–20 min) but lets you audit every line of C++.

## See also

- `AGENTS.md` — full maintainer guide, build reproduction steps, registry
  publishing instructions, compatibility matrix.

## License

The bundled binary inherits the MIT license of upstream `llama.cpp`. The
LocateAnything-3B model weights are subject to NVIDIA's release terms.