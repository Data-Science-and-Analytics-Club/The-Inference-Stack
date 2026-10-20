#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_DIR="${BUNDLE_DIR}/llm-d-upstream"
NAMESPACE="${NAMESPACE:-llm-d-cpu-demo}"
RELEASE="${GUIDE_NAME:-llm-d-cpu-demo}"
BRANCH="${LLM_D_BRANCH:-main}"

for cmd in kubectl helm git; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: required command not found: $cmd" >&2; exit 1; }
done

kubectl get nodes >/dev/null

if [[ ! -d "${UPSTREAM_DIR}/.git" ]]; then
  echo "Cloning llm-d upstream (${BRANCH})..."
  git clone --depth 1 --branch "$BRANCH" https://github.com/llm-d/llm-d.git "$UPSTREAM_DIR"
else
  echo "Using existing checkout: ${UPSTREAM_DIR}"
fi

export REPO_ROOT="$UPSTREAM_DIR"
# shellcheck disable=SC1091
source "${REPO_ROOT}/guides/env.sh"

# Install Gateway API Inference Extension CRDs, including InferencePool.
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/${GAIE_URL}/v1-manifests.yaml"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
# The selected model is public. An empty token is still supplied because the
# upstream model-server wiring expects this Secret to exist. Export HF_TOKEN
# before rerunning if Hugging Face authentication is needed.
kubectl create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN:-}" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

MODEL_DIR="${UPSTREAM_DIR}/guides/optimized-baseline/modelserver/cpu/qwen-small"
mkdir -p "$MODEL_DIR"
cp "${BUNDLE_DIR}/modelserver/kustomization.yaml" "$MODEL_DIR/kustomization.yaml"
cp "${BUNDLE_DIR}/modelserver/patch-small-cpu.yaml" "$MODEL_DIR/patch-small-cpu.yaml"

# Standalone router: EPP + Envoy proxy. The last values file reduces resource
# reservations for a tiny teaching VM; it intentionally trades performance for fit.
helm upgrade --install "$RELEASE" "$ROUTER_STANDALONE_CHART" \
  -f "${REPO_ROOT}/guides/recipes/router/base.values.yaml" \
  -f "${REPO_ROOT}/guides/optimized-baseline/router/optimized-baseline.values.yaml" \
  -f "${BUNDLE_DIR}/router/tiny.values.yaml" \
  --namespace "$NAMESPACE" \
  --version "$ROUTER_CHART_VERSION" \
  --wait --timeout 10m

kubectl apply -n "$NAMESPACE" -k "$MODEL_DIR"

echo
echo "Deployment submitted. Watch startup with:"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo "  kubectl get inferencepool -n ${NAMESPACE}"
echo "  kubectl logs -n ${NAMESPACE} deploy/${RELEASE}-decode -c modelserver -f"
echo
echo "When the model server is Ready, run: ./demo.sh"
