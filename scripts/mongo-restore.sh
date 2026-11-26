#!/usr/bin/env bash
# shellcheck disable=SC2016
# Uso: scripts/mongo-restore.sh [gs://bucket/mongodb/<archivo>.archive.gz]
# Sin argumento restaura el backup más reciente.
set -euo pipefail

NAMESPACE="${NAMESPACE:-quotes}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET="${BUCKET:-${PROJECT_ID}-mongo-backups}"
SOURCE="${1:-}"

if [[ -z "$SOURCE" ]]; then
  SOURCE=$(gcloud storage ls "gs://${BUCKET}/mongodb/" 2>/dev/null | sort | tail -n1 || true)
fi

if [[ -z "$SOURCE" ]]; then
  echo "No hay backups en gs://${BUCKET}/mongodb/" >&2
  exit 1
fi

echo "Backup:  ${SOURCE}"
echo "Destino: ${NAMESPACE}/mongodb-0 (la base quotes se reemplaza)"

if [[ "${FORCE:-0}" != "1" ]]; then
  read -r -p "¿Continuar? [y/N] " answer
  [[ "$answer" == "y" ]] || exit 1
fi

gcloud storage cat "$SOURCE" \
  | kubectl exec -i -n "$NAMESPACE" mongodb-0 -c mongodb -- sh -c \
      'mongorestore --uri="mongodb://root:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017/?authSource=admin" --gzip --archive --drop --nsInclude="quotes.*"'

kubectl exec -n "$NAMESPACE" mongodb-0 -c mongodb -- sh -c \
  'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.getSiblingDB(\"quotes\").quotes.countDocuments()"' \
  | xargs -I{} echo "Documentos en quotes.quotes: {}"
