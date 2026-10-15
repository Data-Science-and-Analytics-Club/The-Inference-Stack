# vLLM Qwen3-8B — Live Demo Runbook

This runbook follows the commands that worked in your terminal session. It is ordered for a live event: demonstrate the running service, explain GPU utilization, run a local chat-completion request, and then demonstrate inference through the external RunPod URL.

## 1. Show the running vLLM service

Run inside the vLLM container:

```
ps aux | grep -E '[v]llm|[a]pi_server'
```

Your output confirmed that the vLLM server was running as PID `57` with model `Qwen/Qwen3-8B`.

Show that it is listening on port 8000:

```
ss -lntp | grep ':8000'
```

Your observed output was:

```
LISTEN 0 2048 0.0.0.0:8000 0.0.0.0:* users:(("vllm",pid=57,fd=22))
```

### Explain this to the audience

- vLLM is the inference engine serving the model.
- Qwen3-8B is the model loaded for text generation.
- Port 8000 is the HTTP API listening port.
- `0.0.0.0` means the server listens on all network interfaces inside its environment.
- PID 57 is the actual Python process running the vLLM server.

The service is exposed externally through the RunPod proxy URL, which forwards requests to port 8000.

## 2. Show GPU status using `nvidia-smi`

Run:

```
nvidia-smi
```

Your observed output:

```
GPU:             NVIDIA RTX A5000
Driver Version:  580.178.04
CUDA Version:    13.0
Memory Usage:    22913 MiB / 24564 MiB
GPU Utilization: 0%
Temperature:     31°C
Power Usage:     24W / 230W
```

### Explain the output

| Metric                      | Meaning                                                        |
| --------------------------- | -------------------------------------------------------------- |
| NVIDIA RTX A5000            | GPU used for model inference.                                  |
| Driver Version 580.178.04   | Installed NVIDIA driver.                                       |
| CUDA Version 13.0           | CUDA compatibility version reported by the driver.             |
| Memory: 22,913 / 24,564 MiB | Approximately 93.3% of GPU memory is occupied or allocated.    |
| GPU Utilization: 0%         | No significant GPU computation was detected during the sample. |
| Temperature: 31°C           | GPU temperature at the time of measurement.                    |
| Power: 24W / 230W           | Current GPU power draw and reported power limit.               |

Key point for the demo: GPU memory usage and GPU utilization are different. vLLM can reserve GPU memory for model weights and the KV cache even when no inference request is actively being processed. During inference, GPU utilization may increase.

The process table reported `No running processes found`; that does not, by itself, establish that vLLM is not using the GPU. The process listing and successful API response provide separate evidence that the service is running.

## 3. Run a local chat-completion request

This is the command that successfully returned HTTP 200 OK in your session. It does not depend on the missing `python` executable.

First, confirm the API key variable is populated:

```
echo "$VLLM_API_KEY"
```

Then run the request from inside the container:

```
curl -sS -i http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [
      {
        "role": "user",
        "content": "Explain Kubernetes in three sentences."
      }
    ],
    "temperature": 0.7,
    "max_tokens": 256
  }'
```

### What the response demonstrates

Your successful response contained:

```
HTTP/1.1 200 OK
server: uvicorn
content-type: application/json
```

The JSON response included:

- `object: "chat.completion"` — confirms a chat-completion response.
- `model: "Qwen/Qwen3-8B"` — identifies the served model.
- `choices[0].message.content` — contains the generated response.
- `usage` — reports prompt and completion token counts.
- `finish_reason: "length"` — indicates generation stopped at the token limit in your observed response.

Your response contained the model's `<think>` reasoning-style content. For a live demonstration, use a more explicit prompt and a suitable token limit if you want a shorter, cleaner answer. Do not assume the output will always have the same format.

## 4. Run inference through the external RunPod URL

The external endpoint is:

[Open the RunPod vLLM endpoint](https://265zg973ktmr2m-8000.proxy.runpod.net/)

Use the following command from a terminal that has `VLLM_API_KEY` set. This can be your host terminal rather than the container terminal.

```
curl -sS -i --max-time 120 \
  https://265zg973ktmr2m-8000.proxy.runpod.net/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [
      {
        "role": "user",
        "content": "Explain how Kubernetes schedules a Pod onto a node, in three concise sentences."
      }
    ],
    "temperature": 0.7,
    "max_tokens": 256
  }'
```

Important: The external command uses the same API key variable as the local command. If you run it on your laptop, ensure that variable is set in that terminal. Do not assume a variable set inside the container is automatically available on your laptop.

### What to explain during the external demo

1. The request is sent to the public RunPod proxy URL instead of `localhost`.
2. The proxy forwards the HTTP request to the vLLM server listening on port 8000.
3. vLLM runs inference with Qwen3-8B and returns an OpenAI-compatible JSON response.
4. The response includes the generated message and token usage information.

A successful `HTTP 200 OK` and a JSON `chat.completion` response confirm that the external inference request worked.

## 5. Event execution order

Use this sequence during the presentation.

01 — Service is running

Run `ps aux` and `ss -lntp` to show the vLLM process and listening port.

02 — GPU resources

Run `nvidia-smi` and explain GPU memory versus utilization.

03 — Local inference

Call `localhost:8000/v1/chat/completions` with the API key and show the successful JSON response.

04 — External inference

Send the same kind of request through the RunPod proxy URL and demonstrate remote access.

The local chat-completion request is confirmed to have worked in your supplied terminal output. The external request above is the corresponding command to run for the event; its success should be verified live rather than assumed.
