#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'No se encontró %s. Crea el archivo .env con las variables de Supabase.\n' "$ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  printf 'Define SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY en .env.\n' >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  printf 'Uso: %s <comando Flutter> [argumentos...]\nEjemplo: %s build apk\n' "$0" "$0" >&2
  exit 2
fi

cd "$ROOT_DIR"
exec flutter "$@" \
  "--dart-define=SUPABASE_URL=$SUPABASE_URL" \
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
