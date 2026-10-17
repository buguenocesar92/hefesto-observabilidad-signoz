# Receta Laravel + OpenTelemetry → SigNoz (DEMOSTRACIÓN)

Laravel es común en Pymes chilenas, así que esta receta vale la pena aunque el
ejecutable de este kit sea el de Node.

**No se ejecutó.** No hay PHP, Docker ni servidor en el entorno donde se
construyó el kit. Ver `docs/07-PRUEBAS-DE-ACEPTACION.md`.

## El paquete y sus requisitos

Verificado en Packagist el 2026-10-16:

| Dato | Valor |
|---|---|
| Paquete | `open-telemetry/opentelemetry-auto-laravel` |
| Versión más reciente | **1.10.0** |
| Licencia | Apache-2.0 |
| PHP | `^8.1` |
| Laravel | `^10.0 \|\| ^11.0 \|\| ^12.0 \|\| ^13.0` |
| Dependencias | `open-telemetry/api ^1.8`, `open-telemetry/sem-conv ^1.38` |

**Verifica la versión antes de fijarla.** En un proyecto real, pon la que
resuelva Composer hoy, no la que estaba buena el día que se armó este kit.

## Instalación

```bash
composer require open-telemetry/opentelemetry-auto-laravel
```

Para **métricas y trazas hacia SigNoz** (self-hosted, sin clave de ingesta) se
necesita además el exportador OTLP. Verifica cuál es la versión vigente en
Packagist antes de fijarlo; no lo dejé clavado aquí para no que el ejemplo
termine instalando algo que ya no corresponde:

```bash
composer show open-telemetry/opentelemetry-auto-laravel
composer search open-telemetry exporter
```

## Configuración

En `.env` de la app (esto vive en la **aplicación del cliente**, no en el kit
de SigNoz):

```dotenv
OTEL_PHP_AUTOLOAD_ENABLED=true

# Servicio. Ponle un nombre que el cliente reconozca en la UI.
OTEL_SERVICE_NAME=api-facturacion

# Endpoint OTLP/gRPC. Sin clave de ingesta en self-hosted.
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
```

Los nombres de variable son los estándar de OpenTelemetry para PHP, tomados de
la especificación de variables de entorno de OpenTelemetry. **No verifiqué que
el paquete `1.10.0` los lea todos tal cual**: confírmalo en la documentación del
propio paquete antes de dar por hecho que la telemetría llega.

## Variables de entorno de OpenTelemetry

El punto de partida es la [referencia oficial de variables de
OpenTelemetry](https://signoz.io/docs/ingestion/opentelemetry-environment-variables/),
que es la fuente que SigNoz enlaza para este tema.

Comunes para PHP:

| Variable | Para qué |
|---|---|
| `OTEL_SERVICE_NAME` | Nombre del servicio. Es lo que agrupa todo en la UI. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Host y puerto del colector. |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` (4317) o `http/protobuf` (4318). |
| `OTEL_TRACES_SAMPLER` | Muestreo. `parentbased_traceidratio` con ratio bajo ahorra recursos. |
| `OTEL_LOG_LEVEL` | Verbozidad del propio SDK. |

## Lo que queda por comprobar

Sé honesto con el cliente sobre esto: **esta receta no se ejecutó**. En
concreto falta confirmar:

1. Que el paquete `1.10.0` esté cargado en el entorno de la app (Laravel tiene
   varias capas de arranque).
2. Que las consultas a base de datos aparezcan como spans (el valor real de
   APM: ver dónde se va el tiempo).
3. Que los nombres de variable anteriores se respeten en esa versión.

Si vas a cobrar por esto, pruébalo en un entorno de pruebas antes. Instrumentar
y que no funcione es el peor resultado posible en una demo.

## La diferencia que esto le vende al cliente

Con Laravel instrumentado, SigNoz muestra **cada consulta SQL** dentro de cada
petición web, con su duración. Cuando el cliente reporte "la app está lenta",
en lugar de adivinar se abre la traza y se ve:

```
GET /facturacion/123          2.310 ms
├─ Controller                  0.120 ms
├─ Auth check                  0.045 ms
├─ SELECT * FROM clientes      0.310 ms
└─ SELECT * FROM facturas ... 1.780 ms   ← acá está el problema
```

Eso no lo da Uptime Kuma. Eso no lo da Umami. Eso es lo que justifica el
servicio.