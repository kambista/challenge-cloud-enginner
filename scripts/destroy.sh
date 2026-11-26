#!/usr/bin/env bash
# Borra todo en orden: charts (para que GKE elimine el LB y el disco de Mongo),
# luego terraform/envs/prd y por último el bootstrap.
# KEEP_BOOTSTRAP=1 conserva las APIs y el bucket del state.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE="${NAMESPACE:-quotes}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
STATE_BUCKET="${PROJECT_ID}-tfstate"

read -r -p "Esto elimina todo en ${PROJECT_ID}. Escribe el project id para confirmar: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "Cancelado."; exit 1; }

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  helm uninstall nginx -n "$NAMESPACE" --wait 2>/dev/null || true

  echo "Esperando que GKE elimine el load balancer del Ingress..."
  for _ in $(seq 1 30); do
    rules=$(gcloud compute forwarding-rules list --global --project "$PROJECT_ID" \
      --filter="description~'${NAMESPACE}/quotes'" --format="value(name)")
    [[ -z "$rules" ]] && break
    sleep 10
  done
  [[ -z "${rules:-}" ]] || echo "Aún quedan forwarding rules: ${rules}. Revisar antes de seguir." >&2

  helm uninstall quotes-api -n "$NAMESPACE" --wait 2>/dev/null || true
  helm uninstall mongodb -n "$NAMESPACE" --wait 2>/dev/null || true
  kubectl delete pvc -n "$NAMESPACE" -l app=mongodb --wait=true
  kubectl delete namespace "$NAMESPACE" --wait=true
fi

terraform -chdir="${ROOT}/terraform/envs/prd" init -input=false >/dev/null
terraform -chdir="${ROOT}/terraform/envs/prd" destroy

negs=$(gcloud compute network-endpoint-groups list --project "$PROJECT_ID" --format="value(name)")
[[ -z "$negs" ]] || echo "Quedaron NEGs huérfanos, borrarlos a mano: ${negs}" >&2

if [[ "${KEEP_BOOTSTRAP:-0}" == "1" ]]; then
  echo "Bootstrap conservado (bucket gs://${STATE_BUCKET})."
  exit 0
fi

BOOTSTRAP="${ROOT}/terraform/bootstrap"
terraform -chdir="$BOOTSTRAP" init -input=false >/dev/null
terraform -chdir="$BOOTSTRAP" state rm google_storage_bucket.tfstate
terraform -chdir="$BOOTSTRAP" destroy
gcloud storage rm --recursive --all-versions "gs://${STATE_BUCKET}"

echo "Proyecto ${PROJECT_ID} limpio."
