#!/usr/bin/env bash
# Usage: scripts/deploy.sh <dev|qa|staging|prod> <image-tag>
# Requires env vars: MOVIE_DB_PASSWORD, CAST_DB_PASSWORD
set -euo pipefail

ENV="${1:?usage: deploy.sh <dev|qa|staging|prod> <image-tag>}"
TAG="${2:?image tag is required}"
: "${MOVIE_DB_PASSWORD:?MOVIE_DB_PASSWORD is not set}"
: "${CAST_DB_PASSWORD:?CAST_DB_PASSWORD is not set}"

case "$ENV" in
  dev)     NODE_PORT=30001 ;;
  qa)      NODE_PORT=30002 ;;
  staging) NODE_PORT=30003 ;;
  prod)    NODE_PORT=30004 ;;
  *) echo "Unknown environment: $ENV" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."      # repo root

echo "=== Deploying tag '$TAG' to namespace '$ENV' (NodePort $NODE_PORT) ==="
kubectl apply -f k8s/namespaces.yaml

# 1. Databases
helm upgrade --install movie-db charts/postgres -n "$ENV" \
  -f values/movie-db.yaml --set auth.password="$MOVIE_DB_PASSWORD" --wait --timeout 3m
helm upgrade --install cast-db charts/postgres -n "$ENV" \
  -f values/cast-db.yaml --set auth.password="$CAST_DB_PASSWORD" --wait --timeout 3m

# 2. Services
helm upgrade --install cast-service charts/fastapiapp -n "$ENV" \
  -f values/cast-service.yaml --set image.tag="$TAG" --wait --timeout 5m
helm upgrade --install movie-service charts/fastapiapp -n "$ENV" \
  -f values/movie-service.yaml --set image.tag="$TAG" --wait --timeout 5m

# 3. Gateway
helm upgrade --install nginx charts/nginx -n "$ENV" \
  -f values/nginx.yaml --set service.nodePort="$NODE_PORT" --wait --timeout 3m

# 4. Smoke test through nginx
echo "=== Smoke test ==="
curl -fsS "http://localhost:$NODE_PORT/healthz"
curl -fsS -o /dev/null "http://localhost:$NODE_PORT/api/v1/movies/docs" && echo "movies OK"
curl -fsS -o /dev/null "http://localhost:$NODE_PORT/api/v1/casts/docs"  && echo "casts OK"

kubectl get pods -n "$ENV"
echo "=== $ENV deployed successfully ==="
