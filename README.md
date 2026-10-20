# From Model to Production: AI Inference Reference

A post-event reference collection for understanding and exploring the engineering behind LLM inference. It connects the concepts from the presentation to two concrete demonstrations: serving Qwen3-8B with vLLM on a rented GPU, and routing requests through llm-d components on Kubernetes.

> **Start here:** If you are new to the stack, read the conceptual guide first. The runbooks are practical references; they are not prerequisites for understanding the architecture.

## Reference index

| Resource | What it covers | Best for |
|---|---|---|
| [From Model to Production: The Engineering Behind AI Inference](docs/from-model-to-production.md) | Models vs. inference engines, remote GPU servers, SSH, ports, DNS, HTTP, `curl`, tokens, prefill/decode, KV cache, PagedAttention, batching, latency/throughput, and the Kubernetes/llm-d connection. | **Start here** — build the mental model before running commands. |
| [vLLM Qwen3-8B — Live Demo Runbook](docs/vllm-qwen3-8b-runbook.md) | Checks for the running vLLM process, GPU inspection with `nvidia-smi`, local API requests, and requests through the RunPod endpoint. | Follow or reproduce the GPU-serving demonstration. |
| [llm-d CPU Demo: vLLM, Envoy and the Endpoint Picker](docs/llm-d-cpu-routing-demo.md) | Kubernetes workloads and Services, InferencePool, Envoy, Endpoint Picker (EPP), direct inference versus routed inference, and router logs. | Understand the inference-aware routing request path. |
| [Inference Stack presentation deck](slides/inference-stack.pdf) | The presentation visuals and high-level narrative for model serving, vLLM, KV-cache management, batching, and inference-aware routing. | Revisit the event's diagrams and slides. |

## Suggested reading order

1. **Build the mental model:** read [From Model to Production](docs/from-model-to-production.md).
2. **See a model server working:** use the [vLLM runbook](docs/vllm-qwen3-8b-runbook.md) to inspect the process, GPU, and API.
3. **Follow a request through routing:** read and, where the environment is available, reproduce the [llm-d CPU demo](docs/llm-d-cpu-routing-demo.md).
4. **Go deeper:** use the primary documentation linked from the conceptual guide and each runbook.

## How the pieces fit together

```text
Client / application
        |
        | HTTP request
        v
Serving endpoint / optional routing layer
        |
        +-------------------------------+
        |                               |
        v                               v
Direct vLLM API                  Envoy + llm-d routing
        |                               |
        |                       Endpoint Picker (EPP)
        |                               |
        |                       selected model endpoint
        +---------------+---------------+
                        |
                        v
                  vLLM model server
                        |
                        v
                 Model inference
                        |
                        v
                  HTTP response
```

The two demos illustrate different layers of the stack. The vLLM runbook focuses on one model server and a GPU-backed environment. The llm-d demo focuses on the routing path and uses a CPU-only VM with one model-server replica. The latter validates component integration; it is **not** a performance benchmark and does not demonstrate multi-replica load balancing.

## Repository layout

```text
.
├── README.md
├── docs/
│   ├── from-model-to-production.md
│   ├── vllm-qwen3-8b-runbook.md
│   └── llm-d-cpu-routing-demo.md
└── slides/
    └── inference-stack.pdf
```

## Before reusing the runbooks

- The vLLM runbook includes an endpoint from the original RunPod session. It may have expired; verify it before use.
- API keys, access tokens, and private SSH keys must stay out of source control. Supply secrets through your shell or secret manager rather than committing them.
- Commands and resource names in the llm-d guide refer to the documented demo environment. Adapt them if your namespace, release, model, ports, or chart differ.
- A successful API response proves that a request worked; it does not by itself establish production readiness, low latency, or high throughput.

## Primary learning resources

- [vLLM documentation](https://docs.vllm.ai/)
- [llm-d documentation](https://llm-d.ai/)
- [Kubernetes concepts](https://kubernetes.io/docs/concepts/)
- [NVIDIA CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/)
- [NVIDIA `nvidia-smi` documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
- [Original PagedAttention paper](https://doi.org/10.1145/3600006.3613165)

---

This repository is intended as post-event learning material. Use the guides to understand the architecture, then experiment in an environment you control and are authorized to access.
