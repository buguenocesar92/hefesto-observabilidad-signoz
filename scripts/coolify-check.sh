#!/usr/bin/env bash
# =============================================================================
# coolify-check.sh — verifica que el compose del kit cumple el contrato Coolify
# =============================================================================
# Lo que verifica:
#
#   1.  Las variables ${VAR} del compose resuelven con un .env temporal
#       poblado con valores ficticios (no secretos: prefijados con `x…`).
#       Esto es puro: NO usa `.env` ni secretos reales.
#
#   2.  En los servicios SIN `profiles:`:
#       - No hay `ports:` (Coolify/Traefik enruta por red Docker al servicio).
#       - No hay `container_name:` (Coolify pone el nombre del proyecto).
#       - No hay `privileged`, `cap_add`, `devices`, `network_mode: host`,
#         `pid: host`, `ipc: host` ni `security_opt: unconfined` (no poder
#         sobre el host).
#       - Los binds son relativos al repo (o absolutos dentro del repo)
#         y NUNCA `docker.sock`.
#
#   3.  El nivel raíz no fija `name:`, y las redes y volúmenes tampoco.
#       Coolify antepone el prefijo del proyecto a esos nombres.
#
# Si algo falla, el script imprime `[coolify-check] FAIL: servicio: motivo`
# y sale con código 1. En verde, imprime un mensaje `OK: …` y sale 0.
#
# Uso:
#   bash scripts/coolify-check.sh
#
# Diseñado para este kit: solo existe `compose.yaml` en la raíz.
# =============================================================================

set -euo pipefail

# --- resolución de rutas ------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${KIT_DIR}/compose.yaml"

# --- helpers ------------------------------------------------------------------
fail() { printf '[coolify-check] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[coolify-check] OK: %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || fail "Falta 'docker' en el PATH."
command -v jq     >/dev/null 2>&1 || fail "Falta 'jq' en el PATH."

[[ -f "${COMPOSE_FILE}" ]] || fail "No se encontró ${COMPOSE_FILE}"

# --- 1. .env temporal con valores ficticios -----------------------------------
TMP_ENV="$(mktemp 2>/dev/null || mktemp -t coolify)"
trap 'rm -f "${TMP_ENV}"' EXIT

# Extrae todas las variables referenciadas del compose (formato ${VAR}, ${VAR:-…}
# o ${VAR:?…}). El doble dólar `$$` es un escape de Compose: `$${VAR}` queda
# como `${VAR}` literal en el comando del contenedor, así que NO se debe contar.
# Por eso reemplazo `$$` por un centinela antes de buscar `${...}`.
VARS="$(
  sed 's/\$\$/<ESCAPED_DOLLAR>/g' "${COMPOSE_FILE}" \
    | grep -oE '\$\{[^}]+\}' \
    | sed -E 's/^\$\{//; s/\}.*//' \
    | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | grep -v '^$' \
    | sort -u
)"

if [[ -z "${VARS}" ]]; then
  fail "No se pudieron extraer variables del compose."
fi

# Variables que esperan formato de URL. Ante la duda les pone un placeholder
# sintácticamente válido; el resto recibe un valor ficticio no secreto.
URL_VARS_RE='^(SIGNOZ_BACKEND_URL|SIGNOZ_FRONTEND_URL|INGESTION_URL)$'

for V in ${VARS}; do
  if [[ "${V}" =~ ${URL_VARS_RE} ]]; then
    echo "${V}=https://ejemplo.invalid" >> "${TMP_ENV}"
  elif [[ "${V}" == *_ADDRESS || "${V}" == *_HOST || "${V}" == *_BIND_ADDRESS ]]; then
    echo "${V}=127.0.0.1" >> "${TMP_ENV}"
  else
    echo "${V}=x1234567890abcdef" >> "${TMP_ENV}"
  fi
done

# --- 2. Render del compose con el .env temporal --------------------------------
RENDER="$(
  docker compose \
    --project-directory "${KIT_DIR}" \
    -f "${COMPOSE_FILE}" \
    --env-file "${TMP_ENV}" \
    config --format json 2>/dev/null \
    || true
)"

[[ -n "${RENDER}" ]] || fail "docker compose config no devolvió contenido."

# --- 3. Servicios SIN profiles: contrato estricto ----------------------------
# Usa la representación renderizada, donde los perfiles ya están resueltos
# y las interpolaciones completadas.
SVC_FILTER='.services | to_entries | map(select(.value.profiles == null)) | map(.key)'
SVCS_NO_PROFILE="$(printf '%s' "${RENDER}" | jq -r "${SVC_FILTER}")"

[[ -n "${SVCS_NO_PROFILE}" ]] || fail "No hay servicios sin profiles en el render."

for SVC in ${SVCS_NO_PROFILE}; do
  # ports: lista, fallo si hay alguna entrada
  PORTS="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].ports // [] | length')"
  if [[ "${PORTS}" -ne 0 ]]; then
    fail "${SVC}: declara 'ports' (${PORTS} entradas). Quítalas: Coolify/Traefik llega por la red Docker del proyecto."
  fi

  # container_name
  CT="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].container_name // empty')"
  [[ -z "${CT}" ]] || fail "${SVC}: usa 'container_name: ${CT}'. Quítalo; Coolify pone el nombre del proyecto."

  # privileged, cap_add, devices
  PRIV="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].privileged // false')"
  [[ "${PRIV}" == "false" ]] || fail "${SVC}: usa 'privileged: true'. No permitido en Coolify."

  CAPS="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].cap_add // [] | length')"
  [[ "${CAPS}" -eq 0 ]] || fail "${SVC}: usa 'cap_add'. No permitido en Coolify."

  DEVS="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].devices // [] | length')"
  [[ "${DEVS}" -eq 0 ]] || fail "${SVC}: usa 'devices'. No permitido en Coolify."

  # network_mode, pid, ipc: ninguno debe ser 'host'
  NETMODE="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].network_mode // empty')"
  [[ "${NETMODE}" != "host" ]] || fail "${SVC}: usa 'network_mode: host'. No permitido en Coolify."

  PID_VAL="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].pid // empty')"
  [[ "${PID_VAL}" != "host" ]] || fail "${SVC}: usa 'pid: host'. No permitido en Coolify."

  IPC_VAL="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].ipc // empty')"
  [[ "${IPC_VAL}" != "host" ]] || fail "${SVC}: usa 'ipc: host'. No permitido en Coolify."

  # security_opt: ningún elemento contiene 'unconfined'
  SEC="$(printf '%s' "${RENDER}" | jq -r --arg s "${SVC}" '.services[$s].security_opt // [] | join(" ")' 2>/dev/null || true)"
  if [[ "${SEC}" == *"unconfined"* ]]; then
    fail "${SVC}: usa 'security_opt: unconfined'. No permitido en Coolify."
  fi

  # binds: solo bind mounts (type=bind). docker.sock prohibido. Si el source
  # es absoluto, debe caer DENTRO del repo (anti path traversal).
  while IFS= read -r src; do
    [[ -z "${src}" ]] && continue
    case "${src}" in
      /var/run/docker.sock|*/docker.sock)
        fail "${SVC}: bindea docker.sock (${src}). No permitido en Coolify."
        ;;
      /*)
        abs="$(cd -- "${src}" 2>/dev/null && pwd || true)"
        if [[ -z "${abs}" || "${abs}" != "${KIT_DIR}"/* ]]; then
          fail "${SVC}: bindea fuera del repo (${src}). No permitido en Coolify."
        fi
        ;;
    esac
  done < <(printf '%s' "${RENDER}" \
              | jq -r --arg s "${SVC}" \
                  '.services[$s].volumes // [] | .[] | select(.type == "bind") | .source // empty')
done

# --- 4. Nombres fijos: ninguno debe quedar ------------------------------------
ROOT_NAME="$(printf '%s' "${RENDER}" | jq -r '.name // empty')"
[[ -z "${ROOT_NAME}" ]] \
  || fail "compose raíz: usa 'name: ${ROOT_NAME}'. Quítalo; Coolify antepone el prefijo del proyecto."

NET_NAMES="$(
  printf '%s' "${RENDER}" \
    | jq -r '.networks // {} | to_entries | map(select(.value.name != null) | .key + "=" + .value.name) | join(" ")' \
    2>/dev/null || true
)"
[[ -z "${NET_NAMES}" ]] \
  || fail "redes con 'name:' fijo: ${NET_NAMES}. Quítalo; Coolify las nombra solo."

VOL_NAMES="$(
  printf '%s' "${RENDER}" \
    | jq -r '.volumes // {} | to_entries | map(select(.value.name != null) | .key + "=" + .value.name) | join(" ")' \
    2>/dev/null || true
)"
[[ -z "${VOL_NAMES}" ]] \
  || fail "volúmenes con 'name:' fijo: ${VOL_NAMES}. Quítalo; Coolify los nombra solo."

pass "compose cumple el contrato de Coolify."
exit 0
