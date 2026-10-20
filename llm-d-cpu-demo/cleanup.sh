#!/usr/bin/env bash
set -euo pipefail
NAMESPACE="${NAMESPACE:-llm-d-cpu-demo}"
RELEASE="${GUIDE_NAME:-llm-d-cpu-demo}"
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found" >&2; exit 1; }
helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || true
kubectl delete namespace "$NAMESPACE" --wait=false 2>/dev/null || true
echo "Demo Helm release removed and namespace deletion requested."
