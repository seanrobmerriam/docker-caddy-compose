#!/bin/sh
set -eu

# Resolve the same interpolation environment that Docker Compose v2 uses.
# Keeping this in a subshell prevents working variables from changing the
# environment inherited by the caller's later Compose commands.
(
  if [ "$#" -ne 2 ]; then
    printf '%s\n' 'usage: resolve-compose-value.sh KEY DEFAULT' >&2
    exit 2
  fi

  __resolve_compose_value_key=$1
  __resolve_compose_value_default=$2

  case $__resolve_compose_value_key in
    ''|[0-9]*|*[!A-Za-z0-9_]*)
      printf 'Invalid Compose variable name: %s\n' "$__resolve_compose_value_key" >&2
      exit 2
      ;;
  esac

  if ! docker compose version >/dev/null 2>&1; then
    printf '%s\n' 'Docker Compose v2 is required to resolve project environment values.' >&2
    exit 1
  fi

  __resolve_compose_value_project_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
  cd "$__resolve_compose_value_project_dir"

  if ! __resolve_compose_value_environment=$(docker compose config --environment); then
    printf 'Could not resolve %s from Docker Compose configuration.\n' "$__resolve_compose_value_key" >&2
    exit 1
  fi

  if __resolve_compose_value_result=$(
    printf '%s\n' "$__resolve_compose_value_environment" |
      awk -v key="$__resolve_compose_value_key" '
        index($0, key "=") == 1 {
          print substr($0, length(key) + 2)
          found = 1
          exit
        }
        END {
          if (!found) {
            exit 1
          }
        }
      '
  ); then
    if [ -n "$__resolve_compose_value_result" ]; then
      printf '%s\n' "$__resolve_compose_value_result"
    else
      printf '%s\n' "$__resolve_compose_value_default"
    fi
  else
    printf '%s\n' "$__resolve_compose_value_default"
  fi
)
