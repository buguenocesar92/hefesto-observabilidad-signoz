# Licencias de los componentes

Todas verificadas el **2026-10-16** leyendo el archivo `LICENSE` de cada
repositorio. Detalle y obligaciones en `docs/10-LICENCIAS-Y-FUENTES.md`.

## Resumen

| Componente | Licencia | Copyleft | Repositorio |
|---|---|---|---|
| SigNoz (aplicación) | **MIT Expat**, con excepción | No | `SigNoz/signoz` |
| SigNoz `ee/` y `cmd/enterprise/` | **SigNoz Enterprise License** | **Sí, comercial** | `SigNoz/signoz` |
| Colector OpenTelemetry de SigNoz | **GNU AGPL v3** | **Sí, fuerte** | `SigNoz/signoz-otel-collector` |
| Foundry (`foundryctl`) | **GNU AGPL v3** | **Sí, fuerte** | `SigNoz/foundry` |
| ClickHouse (server y keeper) | Apache 2.0 | No | `ClickHouse/ClickHouse` |
| PostgreSQL | PostgreSQL License | No | `postgres/postgres` |

## Los tres puntos que hay que mirar

### 1. La app es MIT, pero NO entera

`SigNoz/signoz` es MIT **fuera** de dos directorios:

- `ee/`
- `cmd/enterprise/`

Esos están bajo la **SigNoz Enterprise License**, que dice, textual, que el
software "may only be used in production, if you ... have agreed to and are in
compliance with the SigNoz Subscription Terms of Service ... or otherwise have a
valid SigNoz Enterprise license".

Qué significa en la práctica: operar la edición Community autohospedada es
legítimo. Lo que **no** es legítimo es usar las funciones de `ee/` en
producción sin suscripción. Hefesto opera Community: no actives funciones
Enterprise ni prometas capacidades que estén detrás de esa bandera.

Fuente: <https://github.com/SigNoz/signoz/blob/v0.146.0/LICENSE> y
<https://github.com/SigNoz/signoz/blob/v0.146.0/ee/LICENSE>

### 2. El colector es AGPL v3 — no Apache, no MIT

Este es el que sorprende. El `LICENSE` del repositorio
`SigNoz/signoz-otel-collector` en `v0.144.14` es la **GNU Affero General Public
License v3**, no Apache 2.0. También lo es el de `SigNoz/foundry`.

Qué significa en la práctica: la AGPL obliga a ofrecer el código fuente a
quien **interactúa con el software a través de una red**. En un despliegue
autohospedado donde Hefesto opera la instancia para el cliente, eso es un punto
a revisar con asesoría legal si el servicio se ofrece a terceros.

Lo que Hefesto **sí** hace en este kit, y es lo relevante: **no modifica el
colector**. Solo entrega configuración (YAML y `casting.yaml`). El YAML de
configuración de facto no es código fuente del programa. Aun así, si Hefesto
modificara el colector o vendiera una imagen derivada, la AGPL lo obligaría a
publicar esas modificaciones.

No soy abogado y esto no es asesoría legal. Para una Pyme que autohospeda por su
cuenta, esto es ruido. Para una decisión comercial de revender el servicio,
no lo es: háblalo con tu abogado.

Fuente: <https://github.com/SigNoz/signoz-otel-collector/blob/v0.144.14/LICENSE>

### 3. Foundry también es AGPL v3

`SigNoz/foundry` distribuye el binario `foundryctl` bajo AGPL v3. Instalar y
ejecutar la herramienta es uso ordinario. Este kit no modifica Foundry ni
distribuye binarios propios.

Fuente: <https://github.com/SigNoz/foundry/blob/main/LICENSE>

## Lo que aporta Hefesto

Todo lo demás: `README.md`, `compose.yaml`, `.env.example`, `casting.yaml`
(aunque este sigue el schema público de Foundry), `config/` (copia literal de
los archivos que genera Foundry), `scripts/` y `docs/`.

Hefesto no redistribute código de SigNoz: descarga imágenes Docker oficiales y
entrega configuración. Ver la sección 10 del README.