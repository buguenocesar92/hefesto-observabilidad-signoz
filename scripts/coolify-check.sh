#!/usr/bin/env bash
# =============================================================================
# coolify-check.sh — verifica que el compose del kit cumple el contrato Coolify
# =============================================================================
# Lo que verifica:
#
#   1.  El compose renderiza con `docker compose config` usando un .env
#       temporal con valores ficticios no secretos. NO usa `.env` real.
#
#   2.  En los servicios SIN `profiles:`:
#       - No hay `ports:` (Coolify/Traefik llega por la red Docker).
#       - No hay `container_name:` (Coolify pone el nombre del proyecto).
#       - No hay `privileged`, `cap_add`, `devices`, `network_mode: host`,
#         `pid: host`, `ipc: host` ni `security_opt` con `unconfined`.
#       - Los binds caen dentro del repo y NUNCA son `docker.sock`.
#
#   3.  El archivo no fija `name:` en la raíz, y las redes y volúmenes no
#       tienen un `name:` distinto del que Compose deriva (<proyecto>_<clave>).
#
# Si algo falla imprime `[coolify-check] FAIL: servicio: motivo` y sale 1.
# En verde imprime `[coolify-check] OK: …` y sale 0.
#
# Uso:
#   bash scripts/coolify-check.sh
#   COOLIFY_CHECK_COMPOSE=/ruta/otro.yaml bash scripts/coolify-check.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
COMPOSE_FILE="${COOLIFY_CHECK_COMPOSE:-${KIT_DIR}/compose.yaml}"

fail() { printf '[coolify-check] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[coolify-check] OK: %s\n' "$*"; }

command -v docker   >/dev/null 2>&1 || fail "Falta 'docker' en el PATH."
command -v jq       >/dev/null 2>&1 || fail "Falta 'jq' en el PATH."
command -v realpath >/dev/null 2>&1 || fail "Falta 'realpath' en el PATH."
[[ -f "${COMPOSE_FILE}" ]] || fail "No se encontró ${COMPOSE_FILE}"

cd -- "${KIT_DIR}"

TMP_ENV="$(mktemp)"
TMP_ERR="$(mktemp)"
trap 'rm -f "${TMP_ENV}" "${TMP_ERR}"' EXIT

# --- 1. .env temporal con valores ficticios -----------------------------------
# `$$` es un escape de Compose (queda literal en el contenedor): no se cuenta.
VARS="$(
  sed 's/\$\$/<ESCAPED_DOLLAR>/g' "${COMPOSE_FILE}" \
    | grep -oE '\$\{[^}]+\}' \
    | sed -E 's/^\$\{//; s/^([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u
)" || true
[[ -n "${VARS}" ]] || fail "No se pudieron extraer variables del compose."

for V in ${VARS}; do
  case "${V}" in
    *_HOST|*_URL) echo "${V}=https://ejemplo.invalid" ;;
    *_ADDRESS)    echo "${V}=127.0.0.1" ;;
    *)            echo "${V}=x1234567890abcdef" ;;
  esac
done > "${TMP_ENV}"

# --- 2. Render ------------------------------------------------------------------
if ! RENDER="$(docker compose \
      --project-directory "${KIT_DIR}" \
      -f "${COMPOSE_FILE}" \
      --env-file "${TMP_ENV}" \
      config --format json 2>"${TMP_ERR}")"; then
  fail "docker compose config falló: $(cat "${TMP_ERR}")"
fi
[[ -n "${RENDER}" ]] || fail "docker compose config no devolvió contenido."

# --- 3. Servicios SIN profiles ------------------------------------------------
SVCS_NO_PROFILE="$(jq -r '.services | to_entries[] | select(.value.profiles == null) | .key' <<< "${RENDER}")"
[[ -n "${SVCS_NO_PROFILE}" ]] || fail "No hay servicios sin profiles en el render."

while IFS= read -r SVC; do
  [[ -n "${SVC}" ]] || continue
  q() { jq -r --arg s "${SVC}" "$1" <<< "${RENDER}"; }

  PORTS="$(q '.services[$s].ports // [] | length')"
  [[ "${PORTS}" -eq 0 ]] || fail "${SVC}: declara 'ports' (${PORTS} entradas). Quítalas: Coolify/Traefik llega por la red Docker del proyecto."

  CT="$(q '.services[$s].container_name // empty')"
  [[ -z "${CT}" ]] || fail "${SVC}: usa 'container_name: ${CT}'. Quítalo; Coolify pone el nombre del proyecto."

  [[ "$(q '.services[$s].privileged // false')" == "false" ]] || fail "${SVC}: usa 'privileged: true'. No permitido en Coolify."
  [[ "$(q '.services[$s].cap_add // [] | length')" -eq 0 ]] || fail "${SVC}: usa 'cap_add'. No permitido en Coolify."
  [[ "$(q '.services[$s].devices // [] | length')" -eq 0 ]] || fail "${SVC}: usa 'devices'. No permitido en Coolify."
  [[ "$(q '.services[$s].network_mode // empty')" != "host" ]] || fail "${SVC}: usa 'network_mode: host'. No permitido en Coolify."
  [[ "$(q '.services[$s].pid // empty')" != "host" ]] || fail "${SVC}: usa 'pid: host'. No permitido en Coolify."
  [[ "$(q '.services[$s].ipc // empty')" != "host" ]] || fail "${SVC}: usa 'ipc: host'. No permitido en Coolify."
  if [[ "$(q '.services[$s].security_opt // [] | join(" ")')" == *unconfined* ]]; then
    fail "${SVC}: usa 'security_opt' con unconfined. No permitido en Coolify."
  fi

  while IFS= read -r src; do
    [[ -n "${src}" ]] || continue
    case "${src}" in
      */docker.sock) fail "${SVC}: bindea docker.sock (${src}). No permitido en Coolify." ;;
    esac
    abs="$(realpath -m -- "${src}")"
    if [[ "${abs}" != "${KIT_DIR}" && "${abs}" != "${KIT_DIR}"/* ]]; then
      fail "${SVC}: bindea fuera del repo (${src}). No permitido en Coolify."
    fi
  done < <(q '.services[$s].volumes // [] | .[] | select(.type == "bind") | .source // empty')
done <<< "${SVCS_NO_PROFILE}"

# --- 4. Nombres fijos -----------------------------------------------------------
# El render SIEMPRE trae `.name` y rellena `name:` en redes y volúmenes, así
# que la raíz se revisa en el archivo fuente y redes/volúmenes contra el
# nombre derivado <proyecto>_<clave>.
if grep -qE '^name:' "${COMPOSE_FILE}"; then
  fail "compose raíz: declara 'name:' fijo. Quítalo; Coolify pone el nombre del proyecto."
fi

NET_FIJAS="$(jq -r '.name as $p | [(.networks // {}) | to_entries[] | select(.value.name != null and .value.name != ($p + "_" + .key)) | .key] | join(" ")' <<< "${RENDER}")"
[[ -z "${NET_FIJAS}" ]] || fail "redes con 'name:' fijo: ${NET_FIJAS}. Quítalo; Coolify las nombra solo."

VOL_FIJOS="$(jq -r '.name as $p | [(.volumes // {}) | to_entries[] | select(.value.name != null and .value.name != ($p + "_" + .key)) | .key] | join(" ")' <<< "${RENDER}")"
[[ -z "${VOL_FIJOS}" ]] || fail "volúmenes con 'name:' fijo: ${VOL_FIJOS}. Quítalo; Coolify los nombra solo."

pass "compose cumple el contrato de Coolify."
exit 0
