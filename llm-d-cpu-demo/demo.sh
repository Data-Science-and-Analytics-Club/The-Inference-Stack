#!/usr/bin/env bash
set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-llm-d-cpu-demo}"
RELEASE="${GUIDE_NAME:-llm-d-cpu-demo}"
PORT="${PORT:-8080}"
SVC="${RELEASE}-epp"

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found" >&2; exit 1; }
if ! kubectl get svc "$SVC" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: Service ${SVC} not found in namespace ${NAMESPACE}. Run ./install.sh first." >&2
  exit 1
fi

LOG_FILE="${BUNDLE_DIR}/port-forward.log"
kubectl port-forward -n "$NAMESPACE" "svc/${SVC}" "${PORT}:80" >"$LOG_FILE" 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1; then break; fi
  sleep 1
done

echo "Model list via llm-d router:"
curl -fsS "http://127.0.0.1:${PORT}/v1/models"
echo
echo
echo "Chat completion via llm-d router:"
curl -fsS "http://127.0.0.1:${PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Explain Kubernetes in two short sentences."}],"max_tokens":80,"temperature":0.2}'
echo
