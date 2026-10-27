#!/usr/bin/env bash
# =============================================================================
# restore-signoz.sh — restauración de una instancia SigNoz de Hefesto
# =============================================================================
# Reglas de este script (deliberadamente estrictas):
#
#   1. NUNCA hace DROP ni sobrescribe datos automáticamente.
#   2. Se NEGA a restaurar sobre un destino ocupado, salvo --force explícito.
#   3. Valida los SHA-256 ANTES de tocar nada. Si algo no cuadra, no toca nada.
#   4. Valida las rutas de los archivos (anti path traversal) ANTES de extraer.
#   5. Deja la instancia DETENIDA al terminar. Que una persona revise.
#   6. El metastore se restaura PRIMERO: sin él no hay cuentas ni tableros.
#
# Orden de restauración:
#   a) metastore PostgreSQL  → usuarios, tableros y alertas
#   b) volumen de ClickHouse → telemetría
#   c) volumen de Keeper    → cuórum
#
# ⚠️  Si vas a restaurar sobre una instancia que YA tiene datos, `pg_restore`
#     va a fallar o a mezclar contenido. El script te detiene antes de llegar
#     ahí. El camino correcto es restaurar sobre una instancia vacía.
#
# Uso:
#   ./scripts/restore-signoz.sh --respaldo /var/backups/signoz/signoz-.../
#   ./scripts/restore-signoz.sh --respaldo <ruta> --force   # destino ocupado
# =============================================================================

set -euo pipefail

# --- resolución de rutas ------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${KIT_DIR}/compose.yaml"

RESPALDO=""
FORCE=0
MODO=""
FORCE=0

log()  { printf '[restore] %s\n' "$*"; }
fail() { printf '[restore] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: restore-signoz.sh --respaldo <ruta> [--force]

  --respaldo  Carpeta del respaldo, la que contiene manifest.sha256 y .COMPLETO
  --force     Permite restaurar sobre un destino YA OCUPADO. Sin esto, el
              script se niega.

Ejemplo:
  sudo ./scripts/restore-signoz.sh \
       --respaldo /var/backups/signoz/signoz-20261016T120000Z-pre-actualizar
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --respaldo) RESPALDO="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) MODO="dry-run"; shift ;;
    --confirmar) [[ $# -ge 2 ]] || fail "--confirmar necesita el valor."
                [[ "$2" == "CONFIRMAR_RESTAURACION" ]] || fail "El valor de --confirmar debe ser CONFIRMAR_RESTAURACION."
                MODO="confirmado"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconocido: $1" ;;
  esac
done

[[ -n "${RESPALDO}" ]] || { usage; exit 1; }

# --- Contrato comun de restauracion (docs/CONTRATO-RESPALDO.md) ----------------
# Sin --confirmar CONFIRMAR_RESTAURACION no se restaura nada.
[[ -n "${MODO}" ]] || fail "Falta --confirmar CONFIRMAR_RESTAURACION (o --dry-run para simular sin escribir)."

# --- validación de rutas ------------------------------------------------------
# Pure y antes de tocar Docker o el disco: una ruta inválida se rechaza sin
# efectos secundarios.
[[ "${RESPALDO}" == *".."* ]] && fail "La ruta del respaldo no puede contener '..'."
[[ "${RESPALDO}" == /* ]] || fail "La ruta del respaldo debe ser absoluta."
[[ -d "${RESPALDO}" ]] || fail "No existe el directorio ${RESPALDO}"
[[ "${RESPALDO}" != "${KIT_DIR}"* ]] || fail "El respaldo no puede estar dentro del kit: ${RESPALDO}"
[[ -z "$(find "${RESPALDO}" -maxdepth 0 -type l 2>/dev/null)" ]] || fail "El respaldo no puede ser un symlink."
RESPALDO="$(cd -- "${RESPALDO}" && pwd)"
if ! python3 scripts/respaldo_contrato.py check --dest "${RESPALDO}" \
        --software "hefesto-observabilidad" --version "0.146.0" --database "postgresql+clickhouse"; then
  fail "El respaldo no cumple el contrato de respaldo. NO se restaura."
fi
if [[ "${MODO}" == "dry-run" ]]; then
  log "Simulacion: el respaldo es integro y no se escribio nada."
# --- Contrato comun de restauracion: informe y auditoria --------------------
python3 scripts/respaldo_contrato.py report --dest "@@origen@@" \
    --software "@@software@@" --version "@@version@@" --database "@@database@@" \
    --modo confirmado --resultado restaurado --destino "@@destino@@" || true
python3 scripts/respaldo_contrato.py audit --root "@@destino@@" \
    --software "{software}" --operacion restore \
    --origen "@@origen@@" --destino "@@destino@@" --resultado restaurado || true
  exit 0
fi

# =============================================================================
# 0 — el respaldo debe estar MARCADO como completo
# Todas estas comprobaciones son puras: si el respaldo está incompleto o dañado,
# el script se detiene aquí, ANTES de tocar Docker o el destino.
# =============================================================================
[[ -f "${RESPALDO}/.COMPLETO" ]] || fail "Este respaldo NO está marcado como completo (falta .COMPLETO). Un respaldo a medias no se restaura. Verifica el origen."
[[ -f "${RESPALDO}/manifest.sha256" ]] || fail "Falta manifest.sha256. No puedo verificar la integridad."
[[ -f "${RESPALDO}/postgres-metastore.dump" ]] || fail "Falta postgres-metastore.dump. Es lo más importante del respaldo."

# Validación anti path traversal: los nombres listados en el manifiesto deben ser
# archivos simples dentro de la carpeta del respaldo. Nada de rutas absolutas,
# nada de "../", nada de barras.
#
# IMPORTANTE: el bucle lee con redirección de ARCHIVO, no con process
# substitution (`< <(...)`). Con process substitution el bucle corre en un
# subshell, `fail`/`exit` solo mataría el subshell y el script SEGUIRÍA
# restaurando. Ese bug existió y lo detectó una prueba con un manifiesto
# malicioso.
while IFS= read -r linea || [[ -n "${linea}" ]]; do
  [[ -z "${linea// }" ]] && continue
  suma="${linea%% *}"
  nombre="${linea#* }"
  nombre="${nombre#\*}"
  [[ -n "${nombre}" ]] || continue
  case "${nombre}" in
    ..|/*|\\*|*/*) fail "Ruta sospechosa en manifest.sha256: '${nombre}'" ;;
  esac
  [[ "${#suma}" -eq 64 ]] || fail "SHA-256 inválido en el manifiesto para '${nombre}'"
  [[ -f "${RESPALDO}/${nombre}" ]] || fail "El manifiesto declara '${nombre}' pero no está en la carpeta."
done < "${RESPALDO}/manifest.sha256"

# A partir de aquí sí se necesita Docker.
command -v docker >/dev/null 2>&1 || fail "No se encontró 'docker' en el PATH."
[[ -f "${COMPOSE_FILE}" ]] || fail "No se encontró ${COMPOSE_FILE}"

# =============================================================================
# 1 — verificación de checksums (antes de tocar nada)
# =============================================================================
log "1/5: verifico los SHA-256."
( cd "${RESPALDO}" && sha256sum -c manifest.sha256 ) || fail "Los SHA-256 no verifican. NO se restauró nada."

# =============================================================================
# 2 — destino ocupado
# =============================================================================
cd "${KIT_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
[[ -n "${POSTGRES_PASSWORD:-}" ]] || fail "POSTGRES_PASSWORD no está definido en .env. Sin esto no puedo levantar el metastore."

# Nombres derivados del proyecto Compose (sin container_name ni name: fijos).
# En Coolify, exporta COMPOSE_PROJECT_NAME con el nombre del recurso.
DC=(docker compose -f "${COMPOSE_FILE}")
PROJECT="$("${DC[@]}" config | sed -n '1s/^name: //p')"
[[ -n "${PROJECT}" ]] || fail "No pude resolver el nombre del proyecto Compose."
VOL_POSTGRES="${PROJECT}_signoz-metastore-postgres-0-data"
VOL_CLICKHOUSE="${PROJECT}_signoz-telemetrystore-0-0-data"
VOL_KEEPER="${PROJECT}_signoz-telemetrykeeper-0-data"

log "2/5: compruebo si el destino está ocupado."
DATOS_OCUPADOS=0
declare -a MOTIVOS=()

for v in "${VOL_POSTGRES}" "${VOL_CLICKHOUSE}" "${VOL_KEEPER}"; do
  if docker volume inspect "${v}" >/dev/null 2>&1; then
    # Un volumen existe. Importa si tiene contenido: lo compruebo con un listado.
    # Uso la imagen de Postgres (ya fijada en el kit) para listar: nada de :latest.
    n="$(docker run --rm -v "${v}:/src:ro" postgres:16 sh -c 'ls -A /src 2>/dev/null | wc -l' 2>/dev/null || echo 0)"
    if [[ "${n}" =~ ^[0-9]+$ ]] && [[ "${n}" -gt 0 ]]; then
      DATOS_OCUPADOS=1
      MOTIVOS+=("volumen ${v} tiene ${n} entradas")
    fi
  fi
done

if [[ "${DATOS_OCUPADOS}" -eq 1 ]]; then
  if [[ "${FORCE}" -ne 1 ]]; then
    fail "El destino tiene datos:
$(printf '  - %s\n' "${MOTIVOS[@]}")

NO se restaura para evitar mezclar o pisar datos.
Opciones:
  a) Restaura sobre una instancia VACÍA (lo recomendado).
  b) Reintenta con --force SOLO si respaldaste esos datos antes."
  fi
  log "  --force: los volúmenes con datos se van a sobrescribir. Esto NO se puede deshacer."
  read -r -p "  Escribe SI SEGURO para confirmar: " CONFIRMA
  [[ "${CONFIRMA}" == "SI SEGURO" ]] || fail "Confirmación incorrecta. No se restauró nada."
fi

# =============================================================================
# 3 — metastore PostgreSQL (PRIMERO: sin esto no hay cuentas ni tableros)
# =============================================================================
log "3/5: levanto PostgreSQL vacío y restauro el metastore."
docker compose -f "${COMPOSE_FILE}" up -d signoz-metastore-postgres-0

CT_POSTGRES="$("${DC[@]}" ps -q signoz-metastore-postgres-0)"
[[ -n "${CT_POSTGRES}" ]] || fail "No arrancó signoz-metastore-postgres-0 en el proyecto ${PROJECT}."
IMAGEN_CLICKHOUSE="clickhouse/clickhouse-server:25.12.5"

# Espero a que Postgres acepte conexiones (máximo 120 s).
for i in $(seq 1 60); do
  if docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" "${CT_POSTGRES}" \
       pg_isready -U signoz -d signoz >/dev/null 2>&1; then
    log "  PostgreSQL listo (${i}s)."
    break
  fi
  [[ "${i}" -eq 60 ]] && fail "PostgreSQL no respondió en 120 s. Abortando sin cambios."
  sleep 2
done

# El dump se entra como un objeto nuevo: --clean NO se usa a propósito.
# Nunca borro tablas automáticamente. Si el destino tuviera datos, pg_restore
# fallaría en vez de pisarlos.
log "  restauro con pg_restore (sin --clean, sin DROP)."
docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" "${CT_POSTGRES}" \
  pg_restore -U signoz -d signoz --no-owner --no-privileges --exit-on-error \
  < "${RESPALDO}/postgres-metastore.dump" \
  || fail "pg_restore falló. La base quedó como estaba: revisa el log antes de reintentar."

# =============================================================================
# 4 — volúmenes de telemetría y Keeper
# =============================================================================
if [[ -f "${RESPALDO}/clickhouse-keeper.tar.gz" ]]; then
  log "4/5: restauro el volumen de Keeper."
  # Extraigo dentro del volumen vía un contenedor auxiliar. El `cd /src` y el
  # `--strip` implícito de `tar -C` evitan escribir fuera del volumen.
  docker run --rm -v "${VOL_KEEPER}:/dst" -v "${RESPALDO}:/respaldo:ro" \
    "${IMAGEN_CLICKHOUSE}" sh -c 'tar -xzf /respaldo/clickhouse-keeper.tar.gz -C /dst'
fi

if [[ -f "${RESPALDO}/clickhouse-telemetria.tar.gz" ]]; then
  log "  restauro el volumen de ClickHouse (telemetría). Puede tardar."
  docker run --rm -v "${VOL_CLICKHOUSE}:/dst" -v "${RESPALDO}:/respaldo:ro" \
    "${IMAGEN_CLICKHOUSE}" sh -c 'tar -xzf /respaldo/clickhouse-telemetria.tar.gz -C /dst'
else
  log "  no hay respaldo de telemetría: ClickHouse quedará vacío."
  log "  SIGUIENTE: revisa /api/v1/health y mira 'Logs' en la UI."
  log "  Es aceptable: la telemetria antigua es descartable. Los tableros y"
  log "  las alertas NO lo son, y esos si se restauraron en el paso 3."
fi

# =============================================================================
# 5 — detener todo y entregar el control a una persona
# =============================================================================
log "5/5: detengo la instancia. Que una persona la revise antes de levantarla."
docker compose -f "${COMPOSE_FILE}" stop || true
docker compose -f "${COMPOSE_FILE}" down --remove-orphans || true

cat <<EOF

Restauración terminada. La instancia queda DETENIDA a propósito.

Revisa antes de levantar:
  1. docker volume inspect ${VOL_POSTGRES} --format '{{.Mountpoint}}'
     Confirma que hay archivos de PostgreSQL y no solo directorios vacíos.
  2. Verifica los checksums del respaldo otra vez si vas a conservarlo:
       cd ${RESPALDO} && sha256sum -c manifest.sha256
  3. Los datos restaurados pueden tener antigüedad mayor que la retención
     actual de SigNoz. Al levantar, ClickHouse podría aplicar el TTL y borrar
     telemetría vieja según la política vigente. Si necesitas conservar esa
     telemetría, revisa la retención ANTES de levantar (ver docs/05).

Para levantar:
  docker compose -f compose.yaml up -d
  curl http://localhost:8080/api/v1/health   # debe devolver {"status":"ok"}
EOF
