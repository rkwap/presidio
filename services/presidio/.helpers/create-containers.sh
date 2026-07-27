#!/usr/bin/env bash
set -Eeuo pipefail

token=${PRESIDIO_BEARER_TOKEN:-}
if (( ${#token} < 32 )); then
  printf '%s\n' \
    'PRESIDIO_BEARER_TOKEN must contain at least 32 characters.' >&2
  exit 1
fi
if [[ ! $token =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
  printf '%s\n' \
    'PRESIDIO_BEARER_TOKEN contains unsupported characters.' >&2
  exit 1
fi

script_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
repo_root=$(cd "$script_dir/../../.." && pwd)
caddyfile="$repo_root/services/presidio/auth-proxy/Caddyfile"
recognizer_config="$repo_root/config/india-recognizers.yaml"
network=presidio-local

docker rm -f \
  presidio-analyzer-auth \
  presidio-anonymizer-auth \
  presidio-analyzer \
  presidio-anonymizer \
  >/dev/null 2>&1 || true

docker network inspect "$network" >/dev/null 2>&1 ||
  docker network create "$network" >/dev/null

docker run --detach \
  --name presidio-analyzer \
  --restart unless-stopped \
  --network "$network" \
  --env RECOGNIZER_REGISTRY_CONF_FILE=/app/config/india-recognizers.yaml \
  --volume "$recognizer_config:/app/config/india-recognizers.yaml:ro" \
  ghcr.io/data-privacy-stack/presidio-analyzer:2.2.362

docker run --detach \
  --name presidio-anonymizer \
  --restart unless-stopped \
  --network "$network" \
  ghcr.io/data-privacy-stack/presidio-anonymizer:2.2.362

docker run --detach \
  --name presidio-analyzer-auth \
  --restart unless-stopped \
  --network "$network" \
  --publish 127.0.0.1:5002:8080 \
  --env "PRESIDIO_BEARER_TOKEN=$token" \
  --env UPSTREAM=presidio-analyzer:3000 \
  --volume "$caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.10.2-alpine

docker run --detach \
  --name presidio-anonymizer-auth \
  --restart unless-stopped \
  --network "$network" \
  --publish 127.0.0.1:5001:8080 \
  --env "PRESIDIO_BEARER_TOKEN=$token" \
  --env UPSTREAM=presidio-anonymizer:3000 \
  --volume "$caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.10.2-alpine
