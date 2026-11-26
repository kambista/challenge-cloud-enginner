#!/usr/bin/env bash
# shellcheck disable=SC2016
# Rota la credencial que usa quotes-api sin downtime:
# crea un usuario nuevo, publica la URI en Secret Manager, reinicia la API y borra el usuario anterior.
set -euo pipefail

NAMESPACE="${NAMESPACE:-quotes}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
SECRET_ID="${SECRET_ID:-mongo-uri}"
DATABASE="${DATABASE:-quotes}"

mongo_admin() {
  kubectl exec -i -n "$NAMESPACE" mongodb-0 -c mongodb -- sh -c \
    'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin'
}

CURRENT_URI=$(gcloud secrets versions access latest --secret "$SECRET_ID" --project "$PROJECT_ID")
OLD_USER=$(sed -E 's#^mongodb://([^:]+):.*#\1#' <<<"$CURRENT_URI")
NEW_USER="quotes-api-$(date -u +%Y%m%d%H%M%S)"
NEW_PASS=$(openssl rand -hex 24)
NEW_URI=$(sed -E "s#^mongodb://[^@]+@#mongodb://${NEW_USER}:${NEW_PASS}@#" <<<"$CURRENT_URI")

echo "Usuario actual: ${OLD_USER}"
echo "Usuario nuevo:  ${NEW_USER}"

mongo_admin <<EOF
db.getSiblingDB("${DATABASE}").createUser({
  user: "${NEW_USER}",
  pwd: "${NEW_PASS}",
  roles: [{ role: "readWrite", db: "${DATABASE}" }]
});
EOF

printf '%s' "$NEW_URI" | gcloud secrets versions add "$SECRET_ID" --project "$PROJECT_ID" --data-file=- >/dev/null

kubectl annotate externalsecret quotes-api -n "$NAMESPACE" force-sync="$(date +%s)" --overwrite >/dev/null

for _ in $(seq 1 30); do
  synced=$(kubectl get secret quotes-api -n "$NAMESPACE" -o jsonpath='{.data.mongo-uri}' | base64 -d)
  [[ "$synced" == *"${NEW_USER}:"* ]] && break
  sleep 2
done

if [[ "$synced" != *"${NEW_USER}:"* ]]; then
  echo "El Secret de Kubernetes no se actualizó. Revisar: kubectl describe externalsecret quotes-api -n ${NAMESPACE}" >&2
  echo "El usuario ${OLD_USER} sigue activo; no hubo impacto." >&2
  exit 1
fi

kubectl rollout restart deployment/quotes-api -n "$NAMESPACE"
kubectl rollout status deployment/quotes-api -n "$NAMESPACE" --timeout=5m

mongo_admin <<EOF
db.getSiblingDB("${DATABASE}").dropUser("${OLD_USER}");
EOF

echo "Listo. quotes-api usa ${NEW_USER} y ${OLD_USER} fue eliminado."
