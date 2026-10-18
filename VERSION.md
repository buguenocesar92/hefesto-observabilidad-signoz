# Versiones del kit

Estado del kit: **kit preparado**. Ninguna de estas versiones se ha ejecutado en
un servidor: en este entorno no hay Docker ni servidor. Ver
`docs/07-PRUEBAS-DE-ACEPTACION.md`.

Fecha de verificación: **2026-10-16**.

---

## Versión de la aplicación

| Componente | Imagen | Versión | Origen |
|---|---|---|---|
| Aplicación SigNoz | `signoz/signoz` | `v0.146.0` | GitHub Releases |
| Colector OpenTelemetry | `signoz/signoz-otel-collector` | `v0.144.14` | Docker Hub |
| ClickHouse server | `clickhouse/clickhouse-server` | `25.12.5` | Artefacto de Foundry |
| ClickHouse Keeper | `clickhouse/clickhouse-keeper` | `25.12.5` | Artefacto de Foundry |
| Metastore | `postgres` | `16` | Artefacto de Foundry |

### Digest de `signoz/signoz:v0.146.0`

Verificado en Docker Hub el 2026-10-16:

```
# Manifest list (multi-arch) — el que debes usar en `image:` si fijas por digest
signoz/signoz@sha256:cd3ca6950df3b3681b4629c1b2cea4d3bcd5fece57445a3ec2a1a20466ab14ca

# Sub-manifiestos por arquitectura
linux/amd64  sha256:27cec42dfd398c7afdade4897dd89a489ed3da2441ac1624c369359611da7746
linux/arm64  sha256:1a9295df7165dd25810509fe307b8e5baa9417a2b13f6d0e81657107988e2dd1
```

Para fijar por digest en el casting, usa la forma que acepta el schema:

```yaml
signoz:
  spec:
    image: signoz/signoz@sha256:cd3ca6950df3b3681b4629c1b2cea4d3bcd5fece57445a3ec2a1a20466ab14ca
```

El schema de Foundry acepta `repo:tag` y `repo@sha256:<64 hex>`
(`V1Alpha1MoldingSpec.image`). Verificado en
`https://github.com/SigNoz/foundry/blob/main/api/v1alpha1/installation/casting.schema.json`.

### Digest de los otros componentes: NO verificado

No consulté el digest de `signoz-otel-collector`, `clickhouse-server`,
`clickhouse-keeper` ni `postgres`. Están fijados por etiqueta, no por digest.
Queda como pendiente en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## ⚠️ La app y el colector NO comparten numeración

Esto confunde a todo el mundo la primera vez, así que conviene dejarlo escrito:

- La **aplicación** va en `v0.146.0` (publicada el 2026-10-14).
- El **colector** va en `v0.144.14` (publicada el 2026-10-13).

Consulté `https://hub.docker.com/v2/repositories/signoz/signoz-otel-collector/tags`
y el tag más reciente del colector es `v0.144.14`. La etiqueta
`signoz/signoz-otel-collector:v0.146.0` **no existe** (la API devuelve 404).

No es un error del kit: el colector se versiona por su propia línea. Cuando
actualices la app, revisa aparte cuál es el último tag del colector.

---

## Por qué upstream usa `latest` y este kit no

El artefacto que produce Foundry trae `latest` para `signoz/signoz`,
`signoz/signoz-otel-collector` y `signoz/signoz-mcp-server`. Confirmado leyendo
`casting.yaml.lock` del ejemplo oficial de Foundry.

Hefesto los fija. Un `latest` sin fijar hace que un `docker compose pull`
ilentemente
cambie de versión en producción, sin changelog, sin prueba y sin ventana de
vuelta atrás. Si actualizas, que sea una decisión explícita: cambia la versión
a mano, lee el changelog y prueba.

---

## Foundry (la herramienta que genera los manifiestos)

| Dato | Valor |
|---|---|
| Repositorio | `SigNoz/foundry` |
| Binario | `foundryctl` |
| Licencia | **GNU AGPL v3** (no Apache ni MIT) |
| Archivo fuente | `casting.yaml` |

Instalación documentada por upstream: `./foundry.sh install`.

**Foundry se versiona por separado de SigNoz.** No hay un tag `v0.146.0` de
Foundry. Verifica la versión instalada antes de generar manifiestos, porque el
resultado depende de ella:

```bash
foundryctl version
```

---

## Cambio de arquitectura: por qué este kit no usa `install.sh`

Desde la **v0.130.0**, `install.sh` y los compose de `deploy/` están
deprecados y **ya no se mantienen ni se distribuyen**. La forma soportada es
Foundry.

Fuente: <https://signoz.io/docs/install/docker/> y la nota de la release
<https://github.com/SigNoz/signoz/releases/tag/v0.130.0>.

Ruta de migración sin perder datos: <https://github.com/SigNoz/signoz/blob/main/deploy/MIGRATION.md>

Lo esencial: `deploy/MIGRATION.md` documenta cómo migrar de `deploy/docker-compose`
a `deploy/docker-compose-hotfix` conservando los volúmenes existentes, para no
tener que volver a enviar telemetría ni rehacer tableros y alertas. Los nombres
de volumen del formato antiguo y del nuevo difieren: **no borres los volúmenes
antiguos hasta verificar el nuevo despliegue**.

Detalle en `docs/06-ACTUALIZACIONES-Y-REVERSION.md`.

---

## Retención por defecto (verificada, y corregida)

| Señal | Retención por defecto |
|---|---|
| Logs | 15 días |
| Trazas | 15 días |
| Métricas | 30 días |

Fuente: <https://signoz.io/docs/userguide/retention-period.md> (verificado 2026-10-16).

**No son 7 días.** Esa cifra circulaba en documentación anterior; la doc oficial
vigente dice 15 días para logs y trazas. Si vendes un plan con "7 días", es una
decisión comercial tuya (se configura en la UI), no el valor por defecto.

Dos cosas que la misma doc aclara y que importan al vender:

1. Cambiar la retención **solo aplica a los datos nuevos**. Lo ya guardado
   conserva su retención anterior.
2. Al llegar al TTL los datos se **borran de forma definitiva**. Subir la
   retención después no recupera lo que ya expiró.

---

## Requisitos de recursos

Mínimo oficial: **4 GB de RAM**, Docker Engine 20.10+ con Compose v2, Linux o
macOS (en Windows, WSL2 con Docker nativo).
Fuente: <https://signoz.io/docs/install/docker/>

La guía oficial de
[capacity planning](https://signoz.io/docs/setup/capacity-planning/community/resources-planning.md)
está escrita para despliegues **multi-nodo en producción** (3 colectores, 2
shards de ClickHouse, ZooKeeper de 3 nodos, 100+ GiB de RAM). **No es el
dimensionamiento de una Pyme de un solo VPS.** Upstream no pública una tabla
de dimensionamiento para el despliegue mínimo de un nodo; los 4 GB son el
piso declarado, no un punto de operación comfortable.

Para una Pyme real, con la telemetría de una o dos aplicaciones, la referencia
práctica es 4 vCPU y 8 GB de RAM. Eso es **opinión de Hefesto**, no una cifra de
upstream, y está marcado como tal en `docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Protocolo de actualización

Las minor se mueven pinneando la etiqueta, revisando el changelog y
probando. La guía está en `docs/06-ACTUALIZACIONES-Y-REVERSION.md`.

**Antes de cualquier salto de versión mayor, saca un respaldo** y lee la nota de
la release: las migraciones de esquema de ClickHouse las aplica el servicio
`signoz-telemetrystore-migrator` al arrancar y **no son reversibles automáticamente**.