#!/usr/bin/env bash
# =============================================================================
# backup-signoz.sh — respaldo de una instancia SigNoz de Hefesto
# =============================================================================
# Qué respalda y por qué:
#
#   1. POSTGRES (metastore)  → usuarios, organizaciones, tableros y reglas de
#                              alerta. Es lo ÚNICO que de verdad NO se puede
#                              regenerar. Si pierdes esto, el cliente pierde su
#                              configuración aunque la telemetría siga ahí.
#   2. CLICKHOUSE (telemetría) → trazas, métricas y logs. Volumen entero.
#   3. CLICKHOUSE KEEPER      → estado del cuórum. Pequeño.
#
# Qué NO se respalda:
#   - signoz-telemetrystore-user-scripts: es un binario que se descarga de
#     GitHub en cada arranque. Regenerable.
#   - La telemetría vieja que ya superó su TTL: ya no existe, y expirada es
#     borrada de forma definitiva por ClickHouse.
#
# Coherencia: se detiene la app y el colector (los que escriben), se saca el
# dump de Postgres con el servidor aún arriba (copia consistente por MVCC), y
# solo después se detiene ClickHouse para copiar el volumen en frío.
#
# Uso:
#   ./scripts/backup-signoz.sh --destino /var/backups/signoz
#   ./scripts/backup-signoz.sh --destino /var/backups/signoz --etiqueta antes-de-actualizar
#
# El respaldo solo se marca COMPLETO si TODAS las fases terminan bien.
# Un directorio sin el archivo .COMPLETO es un respaldo incompleto: no lo uses
# para restaurar.
#
# Deja la instancia DETENIDA al terminar, para que nadie siga escribiendo entre
# el respaldo y la próxima operación. Levántala con:
#   docker compose -f compose.yaml up -d
# =============================================================================

set -euo pipefail

# --- resuelvo rutas -----------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${KIT_DIR}/compose.yaml"

DESTINO=""
ETIQUETA="auto"

# --- helpers ------------------------------------------------------------------
log()  { printf '[backup] %s\n' "$*"; }
fail() { printf '[backup] ERROR: %s\n' "$*" >&2; exit 1; }

uso() {
  cat <<'EOF'
Uso: backup-signoz.sh --destino <ruta> [--etiqueta <nombre>]

  --destino   Ruta donde se escribe el respaldo. Se crea si no existe.
  --etiqueta  Nombre descriptivo. Por defecto usa la fecha UTC.

Ejemplo:
  sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz \
       --etiqueta antes-de-actualizar-v0.146
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destino) DESTINO="${2:-}"; shift 2 ;;
    --etiqueta) ETIQUETA="${2:-}"; shift 2 ;;
    -h|--help) uso; exit 0 ;;
    *) fail "Argumento desconocido: $1" ;;
  esac
done

[[ -n "${DESTINO}" ]] || { uso; exit 1; }

# --- validación de rutas (anti path traversal) --------------------------------
# Va ANTES de tocar Docker o el disco: una ruta inválida se rechaza sin efectos.
[[ "${DESTINO}" == *".."* ]] && fail "El destino no puede contener '..': ${DESTINO}"
[[ "${DESTINO}" != /* ]] && fail "El destino debe ser una ruta absoluta: ${DESTINO}"
[[ "${DESTINO}" == "${KIT_DIR}"* ]] && fail "El destino no puede estar dentro del kit: ${DESTINO}"

command -v docker >/dev/null 2>&1 || fail "No se encontró 'docker' en el PATH."

mkdir -p "${DESTINO}"
DESTINO="$(cd -- "${DESTINO}" && pwd)"
[[ "${DESTINO}" == /* ]] || fail "El destino no se pudo resolver a una ruta absoluta."

[[ -f "${COMPOSE_FILE}" ]] || fail "No se encontró ${COMPOSE_FILE}"

cd "${KIT_DIR}"

# --- .env ---------------------------------------------------------------------
# El dump necesita la contraseña de Postgres. Sin .env no hay respaldo coherente.
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  fail "Falta el archivo .env en ${KIT_DIR}. Cópialo desde .env.example y define POSTGRES_PASSWORD."
fi
[[ -n "${POSTGRES_PASSWORD:-}" ]] || fail "POSTGRES_PASSWORD no está definido en .env."

# --- nombres de contenedores (verificados contra compose.yaml) --------------
CT_POSTGRES="signoz-metastore-postgres-0"
CT_CLICKHOUSE="signoz-telemetrystore-clickhouse-0-0"
CT_KEEPER="signoz-telemetrykeeper-clickhousekeeper-0"

VOL_POSTGRES="signoz-metastore-postgres-0-data"
VOL_CLICKHOUSE="signoz-telemetrystore-0-0-data"
VOL_KEEPER="signoz-telemetrykeeper-0-data"

IMAGEN_CLICKHOUSE="clickhouse/clickhouse-server:25.12.5"

for ct in "${CT_POSTGRES}" "${CT_CLICKHOUSE}" "${CT_KEEPER}"; do
  docker inspect "${ct}" >/dev/null 2>&1 || fail "No existe el contenedor ${ct}. ¿Está desplegado el kit?"
done

# --- directorio de salida -----------------------------------------------------
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SAFE_TAG="$(printf '%s' "${ETIQUETA}" | tr -c 'A-Za-z0-9._-' '-' )"
OUT="${DESTINO}/signoz-${TS}-${SAFE_TAG}"
mkdir -p "${OUT}"

log "Respaldo en: ${OUT}"
log "ADVERTENCIA: al terminar la instancia queda DETENIDA."

# Si algo falla a mitad de camino, este directorio queda sin .COMPLETO y
# restore-signoz.sh lo rechazará.
trap 'log "FALLO: respaldo incompleto en ${OUT}. No tiene .COMPLETO: NO usarlo para restaurar."' ERR

# =============================================================================
# FASE 1 — detener los escritores (app + colector)
# =============================================================================
log "Fase 1/5: detengo la app y el colector para dejar de escribir."
docker compose -f "${COMPOSE_FILE}" stop signoz-signoz-0 ingester

# =============================================================================
# FASE 2 — metastore PostgreSQL (lo crítico)
# =============================================================================
log "Fase 2/5: dump del metastore (usuarios, tableros, alertas)."
# --format=custom es el formato de pg_dump: comprimido y restaurable con pg_restore.
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" "${CT_POSTGRES}" \
  pg_dump -U signoz -d signoz --format=custom --compress=9 \
  > "${OUT}/postgres-metastore.dump"

[[ -s "${OUT}/postgres-metastore.dump" ]] || fail "El dump de Postgres quedó vacío."
log "  postgres-metastore.dump: $(du -h "${OUT}/postgres-metastore.dump" | cut -f1)"

# =============================================================================
# FASE 3 — detener ClickHouse y copiar el volumen en frío
# =============================================================================
log "Fase 3/5: detengo ClickHouse y copio el volumen de telemetría."
docker compose -f "${COMPOSE_FILE}" stop signoz-telemetrystore-clickhouse-0-0 signoz-telemetrykeeper-clickhousekeeper-0

log "  copiando ${VOL_CLICKHOUSE} (esto puede tardar: es toda la telemetría)..."
docker run --rm \
  -v "${VOL_CLICKHOUSE}:/src:ro" \
  -v "${OUT}:/backup" \
  "${IMAGEN_CLICKHOUSE}" \
  tar -czf /backup/clickhouse-telemetria.tar.gz -C /src .

[[ -s "${OUT}/clickhouse-telemetria.tar.gz" ]] || fail "El respaldo de ClickHouse quedó vacío."
log "  clickhouse-telemetria.tar.gz: $(du -h "${OUT}/clickhouse-telemetria.tar.gz" | cut -f1)"

# =============================================================================
# FASE 4 — volumen de Keeper
# =============================================================================
log "Fase 4/5: copio el volumen de ClickHouse Keeper."
docker run --rm \
  -v "${VOL_KEEPER}:/src:ro" \
  -v "${OUT}:/backup" \
  "${IMAGEN_CLICKHOUSE}" \
  tar -czf /backup/clickhouse-keeper.tar.gz -C /src .

[[ -s "${OUT}/clickhouse-keeper.tar.gz" ]] || fail "El respaldo de Keeper quedó vacío."

# =============================================================================
# FASE 5 — manifiesto, checksums y marca de completado
# =============================================================================
log "Fase 5/5: manifiesto y checksums SHA-256."

cat > "${OUT}/MANIFIESTO.txt" <<EOF
Respaldo de SigNoz
==================
Fecha (UTC)      : ${TS}
Etiqueta         : ${SAFE_TAG}
Host             : $(hostname)
Versión de imagen: signoz/signoz:v0.146.0 / collector v0.144.14

Contenido
---------
postgres-metastore.dump    Metastore PostgreSQL (formato custom de pg_dump).
                            Incluye usuarios, organizaciones, tableros y reglas
                            de alerta. NO es regenerable. RESTAURAR PRIMERO.
clickhouse-telemetria.tar.gz  Volumen /var/lib/clickhouse: trazas, métricas y
                            logs. Descartable si la retención ya venció.
clickhouse-keeper.tar.gz   Volumen /var/lib/clickhouse-keeper (cuórum).

NO incluido (y por qué)
-----------------------
signoz-telemetrystore-user-scripts  Binario que se descarga de GitHub en cada
                            arranque. Se regenera solo.
.env                     Secretos. NO van en el respaldo: guárdalos aparte, en
                            un gestor de passwords. Si los pierdes, no puedes
                            conectar al metastore.
config/                  Configuración. Está en el repositorio git del kit.

Restaurar con: ./scripts/restore-signoz.sh --respaldo ${OUT}
EOF

# Los checksums se calculan sobre los archivos de datos, no sobre sí mismos.
( cd "${OUT}" && sha256sum \
    postgres-metastore.dump \
    clickhouse-telemetria.tar.gz \
    clickhouse-keeper.tar.gz \
    MANIFIESTO.txt > manifest.sha256 )

# Verifico que los checksums se pueden releer. Un SHA-256 que no verifica no
# sirve de nada.
( cd "${OUT}" && sha256sum -c manifest.sha256 --quiet ) || fail "Los SHA-256 no verifican."

# La marca de completado va AL FINAL, y solo si todo lo anterior pasó.
date -u +"completado_utc=%Y-%m-%dT%H:%M:%SZ" > "${OUT}/.COMPLETO"

trap - ERR

log "OK. Respaldo completo: ${OUT}"
log "La instancia queda DETENIDA. Para levantarla:"
log "  docker compose -f compose.yaml up -d"