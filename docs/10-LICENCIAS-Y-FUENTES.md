# 10 — Licencias y fuentes

Todo lo afirmado en este kit, con su fuente. Si algo no tiene fuente, no
está escrito como hecho.

---

## Licencias de los componentes

Verificadas el **2026-10-16** descargando el archivo `LICENSE` de cada
repositorio.

### SigNoz — aplicación

**MIT Expat**, con una excepción importante.

El `LICENSE` del repositorio dice:

> All content that resides under the "ee/" and the "cmd/enterprise/" directory
> of this repository […] is licensed under the license defined in "ee/LICENSE".
> Content outside of the above mentioned directories […] is available under the
> "MIT Expat" license.

Fuente: <https://github.com/SigNoz/signoz/blob/v0.146.0/LICENSE>

### SigNoz `ee/` y `cmd/enterprise/`

**SigNoz Enterprise License.** El texto dice que el software "may only be used
in production, if you […] have agreed to and are in compliance with the SigNoz
Subscription Terms of Service […] or otherwise have a valid SigNoz Enterprise
license".

**Qué significa para Hefesto:** operar la edición Community autohospedada es
legítimo. Lo que no es es **usar en producción las funciones de `ee/` sin
suscripción**. Hefesto opera Community y no activa capacidades Enterprise.

Fuente: <https://github.com/SigNoz/signoz/blob/v0.146.0/ee/LICENSE>

### Colector OpenTelemetry de SigNoz

**GNU Affero General Public License v3.** El `LICENSE` de
`SigNoz/signoz-otel-collector` en `v0.144.14` es la AGPL v3 completa (34.523
bytes), no Apache 2.0.

Fuente: <https://github.com/SigNoz/signoz-otel-collector/blob/v0.144.14/LICENSE>

### Foundry (`foundryctl`)

**GNU Affero General Public License v3.** El mismo archivo de 34.523 bytes.

Fuente: <https://github.com/SigNoz/foundry/blob/main/LICENSE>

### ClickHouse

**Apache License 2.0.**

Fuente: <https://github.com/ClickHouse/ClickHouse/blob/master/LICENSE>

### PostgreSQL

**PostgreSQL License** (licencia tipo MIT/BSD).

Fuente: <https://github.com/postgres/postgres/blob/master/COPYRIGHT>

---

## Obligaciones reales: qué significa cada licencia

### MIT (app, fuera de `ee/`)

Obligación: conservar el aviso de copyright y el texto de la licencia en las
copias o partes sustanciales.

Para Hefesto: al descargar imágenes Docker oficiales y no redistribuir el
código, no hay reparto de código que entregar. La licencia es permisiva: no hay
que abrir nada.

### Apache 2.0 (ClickHouse)

Obligaciones: mantener avisos de licencia y de copyright; declarar
modificaciones; no usar las marcas.

Para Hefesto: se usa la imagen oficial sin modificar. Nada que hacer.

### PostgreSQL License

Permisiva, tipo MIT. Nada que hacer al usar la imagen oficial.

### AGPL v3 (colector y Foundry) — la que importa

**Qué exige:** si modificas el software, debes ofrecer el código fuente
completo modificado a quienes interactúan con él **a través de una red**.

Consecuencia práctica para una Pyme que autohospeda por su cuenta: está usando
el software sin modificarlo. No hay nada que publicar, porque no hay
modificaciones.

Para Hefesto, las preguntas que importa responder:

1. **¿Hefesto modifica el colector?** No. Este kit entrega configuración
   (YAML y `casting.yaml`), no código. Modificar el collector sí dispararía la
   obligación de publicar esas modificaciones.
2. **¿Hefesto ofrece una instancia compartida a varios clientes?** Ahí la
   pregunta es más delicada: la AGPL apunta a usuarios que interactúan por
   red. Una revisión legal antes de revender el servicio como plataforma es
   prudente.
3. **¿El `compose.yaml` de Hefesto es una obra derivada?** Es configuración de
   despliegue. No es código del programa. Razonablemente no es obra derivada,
   pero es una opinión, no un dictamen legal.

> **Esto no es asesoría legal.** Para una decisión de revender el servicio,
> habla con un abogado. Lo que hay aquí es lectura técnica de las licencias.

---

## Fuentes usadas en este kit

Todas consultadas el 2026-10-16.

### Documentación oficial de SigNoz

| Tema | URL |
|---|---|
| Instalación (requisitos, puertos, Foundry) | <https://signoz.io/docs/install/docker/> |
| Retención | <https://signoz.io/docs/userguide/retention-period/> |
| Usuario raíz | <https://signoz.io/docs/manage/administrator-guide/configuration/root-user/> |
| Bases de datos relacionales | <https://signoz.io/docs/manage/administrator-guide/configuration/relational-database/> |
| Ingesta self-hosted y autenticación | <https://signoz.io/docs/ingestion/self-hosted/overview/> |
| Configuración y variables de entorno | <https://signoz.io/docs/operate/configuration/> |
| Dimensionamiento | <https://signoz.io/docs/setup/capacity-planning/community/resources-planning/> |
| Variables de OpenTelemetry | <https://signoz.io/docs/ingestion/opentelemetry-environment-variables/> |

### Repositorios

| Tema | URL |
|---|---|
| Releases (v0.146.0) | <https://github.com/SigNoz/signoz/releases> |
| Nota de deprecación desde v0.130.0 | <https://github.com/SigNoz/signoz/releases/tag/v0.130.0> |
| Guía de migración de despliegue | <https://github.com/SigNoz/signoz/blob/main/deploy/MIGRATION.md> |
| Foundry (repo) | <https://github.com/SigNoz/foundry> |
| Schema del casting | <https://github.com/SigNoz/foundry/blob/main/api/v1alpha1/installation/casting.schema.json> |
| Ejemplo de compose de Foundry | <https://github.com/SigNoz/foundry/blob/main/docs/examples/docker/compose/pours/deployment/compose.yaml> |
| Colector | <https://github.com/SigNoz/signoz-otel-collector> |
| Configuración de ejemplo de la app | <https://github.com/SigNoz/signoz/blob/main/conf/example.yaml> |

### Docker Hub

| Recurso | URL |
|---|---|
| Tags y digests de `signoz/signoz` | <https://hub.docker.com/v2/repositories/signoz/signoz/tags> |
| Tags de `signoz/signoz-otel-collector` | <https://hub.docker.com/v2/repositories/signoz/signoz-otel-collector/tags> |

### Paquetes de terceros usados en los ejemplos

| Paquete | Fuente | Versión |
|---|---|---|
| `@opentelemetry/sdk-node` | <https://registry.npmjs.org/@opentelemetry/sdk-node> | 0.223.0 (Apache-2.0) |
| `@opentelemetry/auto-instrumentations-node` | <https://registry.npmjs.org/@opentelemetry/auto-instrumentations-node> | 0.81.2 (Apache-2.0) |
| `@opentelemetry/api` | <https://registry.npmjs.org/@opentelemetry/api> | 1.9.1 (Apache-2.0) |
| `open-telemetry/opentelemetry-auto-laravel` | <https://packagist.org/packages/open-telemetry/opentelemetry-auto-laravel> | 1.10.0 (Apache-2.0) |

---

## Qué afirma este kit y de dónde sale cada afirmación

| Afirmación | Fuente |
|---|---|
| `install.sh` y `deploy/` deprecados desde v0.130.0 | Doc de instalación + release v0.130.0 |
| Foundry genera los manifiestos desde `casting.yaml` | Doc de instalación + README de Foundry |
| Puertos 8080, 4317, 4318, 8000 (MCP) | Doc de instalación |
| Mínimo 4 GB RAM, Docker 20.10+ Compose v2 | Doc de instalación |
| Healthcheck `/api/v1/health` devuelve `{"status":"ok"}` | Artefacto de Foundry + doc |
| Los healthchecks de Postgres, ClickHouse y Keeper | Artefacto de Foundry (leídos, no inventados) |
| El colector **no** tiene healthcheck upstream | Artefacto de Foundry |
| Postgres es solo metastore; ClickHouse es obligatorio | Doc de bases de datos relacionales + `telemetrystore.kind` del schema |
| Retención 15/15/30 días | Doc de retención |
| La retención solo afecta datos nuevos y el TTL borra definitivamente | Doc de retención |
| Self-hosted no usa claves de ingesta | Doc de ingesta self-hosted |
| CORS permite solo `localhost:8080` y `:8081` por defecto | Doc de ingesta self-hosted |
| Variables del root user | Doc de usuario raíz |
| Reglas de nombres de variables | Doc de configuración |
| La app es v0.146.0 y el colector v0.144.14 | GitHub Releases y Docker Hub |

## Lo que este kit NO afirma porque no se verificó

- Si la edición Community limita el número de alertas o paneles.
- La matriz exacta de roles en la v0.146.0.
- El nombre exacto de la pantalla para desactivar globalmente el registro.
- Si el campo `env` del casting se propaga al compose generado.
- El comportamiento de los enlaces públicos de tableros en esta versión.
- Cuánto disco consume un cliente real.

Cada uno está anotado en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## Atribución de lo que aporta Hefesto

| Parte | Origen | Licencia |
|---|---|---|
| `compose.yaml` | Copia revisada del artefacto de Foundry | Sigue la de SigNoz (MIT) / los componentes |
| `casting.yaml` | Escrito por Hefesto según el schema público | Hefesto |
| `config/*.yaml` | **Copia literal** de `foundryctl cast` | AGPL v3 (del colector) |
| `scripts/*` | Hefesto | Hefesto |
| `docs/*`, `ejemplos/*`, `README.md` | Hefesto | Hefesto |
| Imágenes Docker | Upstream | Las de cada componente |

`config/` son archivos generados por Foundry, copiados sin modificar, para
permitir el despliegue directo sin instalar `foundryctl`. Si prefieres
regenerarlos en vez de usar la copia:

```bash
foundryctl cast --file casting.yaml --output-dir ./pours
```