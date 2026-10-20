# llm-d CPU demo for a small k3s VM

This is a **best-effort teaching/demo template** for a single-node, CPU-only k3s cluster. It uses the official llm-d standalone router + Gateway API Inference Extension (GAIE) InferencePool/EPP pattern, and adapts the upstream model-server building blocks to serve `Qwen/Qwen2.5-0.5B-Instruct` with vLLM's CPU image.

## Important limits

- The official llm-d CPU well-lit path targets a 3B model and calls for 64 CPU cores and 64 GiB RAM per model-server replica. Your 11 GiB KVM VM is **not** sized for that supported configuration.
- This template shrinks the model to 0.5B, uses one replica, and reduces resource reservations so you can attempt an architecture demo. It is not production sizing, and performance may be slow.
- This assumes a Linux x86_64 KVM guest, a Ready k3s node, internet access from the VM, `kubectl`, `helm`, and `git`. The public Hugging Face model normally does not require a token, but download rate limits may happen.
- If the VM has fewer than 4 vCPUs or the model-server pod OOM-kills, increase VM resources if possible. A 16 GiB VM would provide more headroom.
- This bundle was not runtime-tested against your VM. Upstream `main` and chart dependencies can change; this script uses the version variables in the checked-out llm-d `guides/env.sh`.

## Install

```bash
unzip llm-d-cpu-demo.zip
cd llm-d-cpu-demo
# Optional for Hugging Face auth/rate limits:
# export HF_TOKEN=hf_...
./install.sh
```

The script clones the official llm-d repository to `./llm-d-upstream`, applies the GAIE CRDs, creates the namespace/secret, installs the standalone llm-d router with demo-sized resources, then deploys the small CPU model server.

## Demo a request

In one terminal:

```bash
cd llm-d-cpu-demo
./demo.sh
```

The script port-forwards the llm-d router's `-epp` Service to `localhost:8080`, checks `/v1/models`, then sends an OpenAI-compatible chat completion request. You can also test it manually:

```bash
kubectl port-forward -n llm-d-cpu-demo svc/llm-d-cpu-demo-epp 8080:80
```

In another terminal:

```bash
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Explain Kubernetes in two sentences."}],"max_tokens":80,"temperature":0.2}'
```

## Observe the architecture

```bash
kubectl get pods,svc -n llm-d-cpu-demo
kubectl get inferencepool -n llm-d-cpu-demo
kubectl logs -n llm-d-cpu-demo deploy/llm-d-cpu-demo-decode -c modelserver -f
kubectl logs -n llm-d-cpu-demo deploy/llm-d-cpu-demo-epp -f
```

Names created by Helm charts can differ slightly between upstream revisions; inspect `kubectl get deploy,svc -n llm-d-cpu-demo` if a named resource differs.

**What to explain during the talk:** vLLM is the model-serving runtime; the Kubernetes Deployment runs the model server; the GAIE `InferencePool` represents the serving endpoints; llm-d's Endpoint Picker (EPP) evaluates the pool for LLM-aware request routing; the standalone Envoy proxy provides the HTTP entry point. With one replica, you can show the control/data path but not demonstrate meaningful load balancing. To show routing across replicas, use a larger host and deploy at least two model-server replicas.

## Troubleshooting

```bash
kubectl get pods -n llm-d-cpu-demo -o wide
kubectl describe pod -n llm-d-cpu-demo <pod-name>
kubectl logs -n llm-d-cpu-demo <pod-name> --all-containers --tail=200
kubectl get events -n llm-d-cpu-demo --sort-by=.lastTimestamp
```

- **OOMKilled / exit 137:** reduce memory pressure elsewhere or increase VM RAM; the current VM is tight.
- **ImagePullBackOff:** check VM internet/DNS and `kubectl describe pod` events.
- **Pod pending:** inspect resource requests and `kubectl describe node` allocatable CPU/RAM.
- **Model download/rate-limit error:** export a valid `HF_TOKEN` and rerun `./install.sh`.
- **No matching endpoints / 503:** check that the model-server pod is Ready and has label `llm-d.ai/guide=optimized-baseline`; the InferencePool/EPP can only route to ready compatible endpoints.
- **CPU runtime / unsupported instruction error:** this depends on the CPU features exposed by KVM and the image. Use `--dtype=float32` as configured; if the runtime still fails, this VM may not expose a suitable CPU feature set for vLLM.

## Cleanup

```bash
./cleanup.sh
```

This uninstalls the Helm release and deletes the demo namespace. It leaves the cloned `llm-d-upstream` checkout and local template files on disk.
