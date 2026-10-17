# Demo Node.js + OpenTelemetry → SigNoz (DEMOSTRACIÓN)

App Express mínima, instrumentada con OpenTelemetry, que manda trazas,
métricas y logs a la instancia de SigNoz del kit.

**No se ejecutó.** No hay Docker ni servidor en el entorno donde se construyó
este kit. Ver `docs/07-PRUEBAS-DE-ACEPTACION.md`.

## Archivos

| Archivo | Qué hace |
|---|---|
| `otel.js` | Inicializa el SDK. Debe cargarse **antes** que la app. |
| `server.js` | La app de demostración. |
| `package.json` | Dependencias con versiones fijadas. |

## Versiones

Consultadas en el registro de npm el 2026-10-16:

| Paquete | Versión | Licencia |
|---|---|---|
| `@opentelemetry/sdk-node` | 0.223.0 | Apache-2.0 |
| `@opentelemetry/auto-instrumentations-node` | 0.81.2 | Apache-2.0 |
| `@opentelemetry/api` | 1.9.1 | Apache-2.0 |
| `@opentelemetry/exporter-trace-otlp-grpc` | 0.223.0 | Apache-2.0 |

Node requerido por `sdk-node`: `^18.19.0 || >=20.6.0`.

**Verifica las versiones antes de fijarlas en un proyecto real.** El SDK de
OpenTelemetry para JavaScript cambia rápido: 0.223 es mucho mayor que la 0.100.

> **Ojo con la API de recursos.** `@opentelemetry/resources` va en 2.x y la forma
> de construir el recurso cambió respecto de las versiones 1.x
> (`resourceFromAttributes`). La firma exacta depende de la versión que
> instales: revísala en la documentación de esa versión. No pude ejecutar este
> ejemplo, así que eso quedó sin comprobar.

## Cómo levantarlo

```bash
cd ejemplos/node
npm install

# En una terminal
node --require ./otel.js server.js
```

En otra, genera tráfico:

```bash
for i in $(seq 1 20); do curl -s http://localhost:3000/rapida > /dev/null; done
for i in $(seq 1 10); do curl -s http://localhost:3000/lenta  > /dev/null; done
for i in $(seq 1 20); do curl -s http://localhost:3000/falla  > /dev/null; done
```

## Qué mirar en SigNoz

| Señal | Dónde | Qué deberías ver |
|---|---|---|
| Trazas | *Traces* | Una traza por request. `/lenta` tarda ~250 ms, `/rapida` es inmediata. |
| Métricas | *Metrics* | `demo_latencia_ms` (histograma) y `demo_peticiones_total`. |
| Logs | *Logs* | Las líneas `[demo]` que escriben las rutas. |

## Ajustar la demo

```bash
# Hacer la ruta lenta más lenta, para que el p95 se note
DEMO_LATENCIA_MS=2000 node --require ./otel.js server.js

# Subir la tasa de error al 100 % para disparar la alerta de ejemplo
DEMO_RATE_ERROR=1.0 node --require ./otel.js server.js
```

## Si la app corre en otra máquina

```bash
OTEL_EXPORTER_OTLP_HOST=10.0.0.5 OTEL_EXPORTER_OTLP_PORT=4317 \
  node --require ./otel.js server.js
```

Y en el servidor, el OTLP tiene que aceptar conexiones remotas. El `compose.yaml`
de este kit deja 4317 y 4318 atados a `127.0.0.1` **a propósito**.

Si los cambias, ten presente: **SigNoz self-hosted no pide clave de ingesta**.
Quien alcance el puerto puede escribir telemetría en la instancia de tu cliente.
Lee la sección de puertos OTLP en `docs/08-SERVICIOS-COMERCIALES.md` antes de
exponerlos.

## Para producción

Esto es una demo. Antes de ponerla en un cliente:

1. Cambia el nombre del servicio a algo reconocible
   (`OTEL_SERVICE_NAME=api-facturacion`).
2. Quita la simulación de errores y latencia de `server.js`.
3. Evalúa muestreo: a volumen alto, muestrear evita gastar RAM y disco sin perder
   utilidad.
4. Decide si mandas logs a SigNoz o solo a tu sistema de logs actual. Duplicar
   logs cuesta disco.