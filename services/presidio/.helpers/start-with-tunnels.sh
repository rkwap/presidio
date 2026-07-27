#!/usr/bin/env bash
set -Eeuo pipefail

ANALYZER_SERVICE=presidio-analyzer
ANONYMIZER_SERVICE=presidio-anonymizer
ANALYZER_AUTH=presidio-analyzer-auth
ANONYMIZER_AUTH=presidio-anonymizer-auth
ANALYZER_TUNNEL=presidio-analyzer-quick-tunnel
ANONYMIZER_TUNNEL=presidio-anonymizer-quick-tunnel
CLOUDFLARED_IMAGE=cloudflare/cloudflared:latest

pause_on_exit() {
  local status=$?

  if (( status != 0 )); then
    printf '\nStartup failed with status %d.\n' "$status" >&2
    docker stop "$ANALYZER_TUNNEL" "$ANONYMIZER_TUNNEL" \
      >/dev/null 2>&1 || true
  fi

  if [[ -t 0 ]]; then
    printf '\nPress Enter to close...'
    read -r || true
  fi

  exit "$status"
}
trap pause_on_exit EXIT

wait_for_health() {
  local container=$1
  local attempt health restart_attempt

  for restart_attempt in 0 1; do
    for attempt in {1..90}; do
      health=$(docker inspect "$container" \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')
      [[ $health == healthy || $health == running ]] && return 0
      sleep 1
    done

    if (( restart_attempt == 0 )); then
      printf '%s did not become ready; restarting it once.\n' "$container" >&2
      docker restart "$container" >/dev/null
    fi
  done

  printf '%s did not become ready after one restart.\n' "$container" >&2
  return 1
}

start_tunnel() {
  local name=$1
  local origin=$2
  local attempt logs url

  if docker container inspect "$name" >/dev/null 2>&1; then
    if [[ $(docker inspect "$name" --format '{{.State.Running}}') != true ]]; then
      docker rm -f "$name" >/dev/null
    fi
  fi

  if ! docker container inspect "$name" >/dev/null 2>&1; then
    docker run --detach --rm \
      --name "$name" \
      --network host \
      "$CLOUDFLARED_IMAGE" \
      tunnel --no-autoupdate --protocol http2 --url "$origin" >/dev/null
  fi

  for attempt in {1..60}; do
    logs=$(docker logs "$name" 2>&1 || true)
    url=$(printf '%s' "$logs" |
      grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' |
      head -1 || true)

    if [[ -n $url ]] &&
      printf '%s' "$logs" | grep -q 'Registered tunnel connection'; then
      printf '%s\n' "$url"
      return 0
    fi
    sleep 1
  done

  docker logs "$name" >&2 || true
  printf '%s did not register within 60 seconds.\n' "$name" >&2
  return 1
}

if ! systemctl is-active --quiet docker; then
  sudo systemctl start docker
fi

docker start \
  "$ANALYZER_SERVICE" \
  "$ANONYMIZER_SERVICE" \
  "$ANALYZER_AUTH" \
  "$ANONYMIZER_AUTH" \
  >/dev/null
wait_for_health "$ANALYZER_SERVICE"
wait_for_health "$ANONYMIZER_SERVICE"
wait_for_health "$ANALYZER_AUTH"
wait_for_health "$ANONYMIZER_AUTH"

docker image inspect "$CLOUDFLARED_IMAGE" >/dev/null 2>&1 ||
  docker pull "$CLOUDFLARED_IMAGE"

analyzer_url=$(start_tunnel "$ANALYZER_TUNNEL" http://127.0.0.1:5002)
anonymizer_url=$(start_tunnel "$ANONYMIZER_TUNNEL" http://127.0.0.1:5001)

printf '\nPresidio is running.\n'
printf 'Analyzer:   %s\n' "$analyzer_url"
printf 'Anonymizer: %s\n' "$anonymizer_url"
printf '\nThese URLs are public and unauthenticated. Use synthetic test data only.\n'
