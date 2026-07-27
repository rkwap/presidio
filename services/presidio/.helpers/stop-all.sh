#!/usr/bin/env bash
set -Eeuo pipefail

pause_on_exit() {
  local status=$?

  if (( status != 0 )); then
    printf '\nShutdown failed with status %d.\n' "$status" >&2
  fi

  if [[ -t 0 ]]; then
    printf '\nPress Enter to close...'
    read -r || true
  fi

  exit "$status"
}
trap pause_on_exit EXIT

stop_if_present() {
  local name=$1

  if docker container inspect "$name" >/dev/null 2>&1; then
    docker stop "$name" >/dev/null
    printf 'Stopped %s\n' "$name"
  else
    printf '%s was already stopped or absent\n' "$name"
  fi
}

if ! systemctl is-active --quiet docker; then
  printf 'Docker is not running; Presidio and its tunnels are already stopped.\n'
  exit 0
fi

stop_if_present presidio-analyzer-quick-tunnel
stop_if_present presidio-anonymizer-quick-tunnel
stop_if_present presidio-analyzer-auth
stop_if_present presidio-anonymizer-auth
stop_if_present presidio-analyzer
stop_if_present presidio-anonymizer

printf '\nPresidio and its temporary tunnels are stopped.\n'
