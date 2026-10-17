# 03 — Variables de entorno y cómo obtenerlas

Todas las variables que usa este kit, de dónde sale cada una y qué pasa si la
cambias después.

> Cada fila indica si el nombre fue **verificado** contra documentación oficial
> o contra el artefacto que produce Foundry. No hay nombres inventados: si algo
> no estaba verificado, no está en esta tabla.

---

## Variables del `.env` de Hefesto

Estas las usa el `compose.yaml` de este kit.

### `POSTGRES_PASSWORD`

| | |
|---|---|
| Obligatoria | **Sí** |
| Ejemplo | `k3Nq7bX2mR9tVw5zLpQ8hYdF` (falso) |
| De dónde sale | La generas tú |
| Cómo | `openssl rand -base64 24 \| tr -d '/+=' \| cut -c1-32` |
| Por qué alfanumérica | Se interpola dentro de una URL DSN (`postgres://signoz:<pass>@host:5432/signoz`). Un `#` o un `@` rompen la URL. |
| Si la cambias después | **Rompes el metastore.** Postgres no acepta cambiar la contraseña del usuario por variable de entorno: hay que entrar a la base y hacer `ALTER USER signoz WITH PASSWORD '...'`. Actualiza también `SIGNOZ_SQLSTORE_POSTGRES_DSN` (el compose la arma desde esta variable). |
| Origen del nombre | Artefacto de Foundry (servicio `signoz-metastore-postgres-0`) + doc de bases relacionales |

### `SIGNOZ_USER_ROOT_ENABLED`

| | |
|---|---|
| Obligatoria para el primer despliegue | **Sí**, en la práctica |
| Valores | `true` / `false` |
| Por defecto en el kit | `false` |
| Qué hace | Crea el usuario administrador raíz en el arranque |
| Si la cambias después | Requiere **reiniciar** SigNoz: el aprovisionamiento corre solo al inicio |
| Origen | <https://signoz.io/docs/manage/administrator-guide/configuration/root-user/> (disponible desde **v0.112.0**) |

### `SIGNOZ_USER_ROOT_EMAIL`

| | |
|---|---|
| Obligatoria | Sí, si `SIGNOZ_USER_ROOT_ENABLED=true` |
| Ejemplo | `admin@tucliente.cl` |
| Si la cambias después | Reinicia. El root user **no se puede editar desde la UI** |
| Origen | Misma fuente que arriba |

### `SIGNOZ_USER_ROOT_PASSWORD`

| | |
|---|---|
| Obligatoria | Sí, si `SIGNOZ_USER_ROOT_ENABLED=true` |
| Ejemplo | (no pongas el ejemplo real acá) |
| Cómo generarla | Gestor de passwords. Como alternativa: `openssl rand -base64 32` |
| Si la cambias después | Reinicia. No se puede cambiar desde la UI |
| ⚠️ | **Bórrala del `.env` cuando confirmes que puedes entrar.** Quedó como variable del compose para el primer arranque; después es una contraseña guardada en texto plano en el servidor. |

### `SIGNOZ_USER_ROOT_ORG_NAME`

| | |
|---|---|
| Obligatoria | Sí, si `SIGNOZ_USER_ROOT_ENABLED=true` |
| Ejemplo | `default` o el nombre del cliente |
| Importante | En una instancia existente, **debe coincidir** con el nombre de la organización en la base, o el root user no se asocia a la organización correcta |
| Si la cambias después | En una instancia ya creada, primero hay que actualizar la tabla `organizations` en el metastore. Ver la doc de root user. |
| Origen | Misma fuente que arriba |

Existe además `SIGNOZ_USER_ROOT_ORG_ID` (UUID v7, opcional), documentada en la
misma fuente. Este kit no la usa: con una instancia por cliente, el nombre
alcanza.

### `SIGNOZ_BIND_ADDRESS`

| | |
|---|---|
| Obligatoria | No |
| Por defecto en el kit | `127.0.0.1` |
| Valores | `127.0.0.1` (solo local) o `0.0.0.0` (todas las interfaces) |
| Aplica a | Variable **de Hefesto**, no de SigNoz. Controla el bind del puerto 8080 en el compose |
| Si la cambias después | Requiere redeploy |

---

## Variables de la aplicación SigNoz

Estas van **dentro** del `compose.yaml`, no en el `.env`. Se documentan porque
hay que entenderlas para operar.

| Variable | Servicio | Valor en el kit | Para qué |
|---|---|---|---|
| `SIGNOZ_SQLSTORE_PROVIDER` | `signoz-signoz-0` | `postgres` | Selecciona el motor del metastore |
| `SIGNOZ_SQLSTORE_POSTGRES_DSN` | `signoz-signoz-0` | `postgres://signoz:${POSTGRES_PASSWORD}@signoz-metastore-postgres-0:5432/signoz?sslmode=disable` | Conexión al metastore |
| `SIGNOZ_TELEMETRYSTORE_PROVIDER` | `signoz-signoz-0` | `clickhouse` | Motor de telemetría |
| `SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN` | `signoz-signoz-0` | `tcp://signoz-telemetrystore-clickhouse-0-0:9000` | Conexión a ClickHouse |

Origen: artefacto de Foundry (`pours/deployment/compose.yaml`).

### Sobre `sslmode=disable`

El compose de upstream lo usa porque Postgres y SigNoz se comunican **por la
red interna de Docker**, donde el tráfico no sale del host.

**Esto solo es aceptable con Postgres dentro del compose.** Si algún día
mueves el metastore a una base remota, `sslmode=disable` queda prohibido: en ese
caso hay que poner `sslmode=require` (o `verify-full`) y cambiar el
`SIGNOZ_SQLSTORE_POSTGRES_DSN` en consecuencia.

### Sobre Supabase

El contrato de Hefesto pide evaluar Supabase cuando la app usa PostgreSQL. Aquí
la respuesta es:

**Supabase solo sirve para el metastore, y no lo recomiendo sin pruebas.**

- Se puede: `SIGNOZ_SQLSTORE_POSTGRES_DSN` es un DSN de Postgres estándar y
  Supabase sirve Postgres. Técricamente conectaría.
- **Pero no lo verifiqué**: versión exacta de Postgres que exige SigNoz,
  extensiones requeridas, comportamiento de TLS desde la red de Coolify, ni el
  uso de superusuario que hace el migrador (necesita crear tablas y migrarlas).
- Y sobre todo: **Supabase no reemplaza a ClickHouse**. ClickHouse sigue siendo
  obligatorio para la telemetría. Supabase no resuelve el problema de disco de
  los datos de observabilidad, que es el que más duele.

Por eso este kit **no ofrece Supabase** como opción. Si alguien la pide, se
trata como proyecto aparte, con pruebas. Ver la sección de Supabase en
`08-SERVICIOS-COMERCIALES.md`.

---

## Variables del colector

| Variable | Servicio | Valor en el kit | Para qué |
|---|---|---|---|
| `SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN` | `ingester` y `migrator` | `tcp://signoz-telemetrystore-clickhouse-0-0:9000` | DSN de ClickHouse del colector |
| `SIGNOZ_OTEL_COLLECTOR_TIMEOUT` | `ingester` y `migrator` | `10m` | Tiempo máximo de espera |

Origen: artefacto de Foundry.

---

## Variables de la aplicación cliente

Estas **no** van en este kit: van en la aplicación que se quiere monitorear.

| Variable | Ejemplo | Para qué |
|---|---|---|
| `OTEL_SERVICE_NAME` | `api-facturacion` | Nombre del servicio. Es lo que agrupa todo en la UI |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://127.0.0.1:4317` | Dónde está el colector |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | `grpc` (4317) o `http/protobuf` (4318) |
| `OTEL_TRACES_SAMPLER` | `parentbased_traceidratio` | Muestreo de trazas |
| `OTEL_TRACES_SAMPLER_ARG` | `0.1` | Qué fracción se guarda (0.1 = 10 %) |

Son variables estándar de OpenTelemetry, no proprietarias de SigNoz. Referencia:
<https://signoz.io/docs/ingestion/opentelemetry-environment-variables/>

**Sobre la sampling:** es la palanca más efectiva para controlar el consumo. Con
volumen alto, `OTEL_TRACES_SAMPLER_ARG=0.1` reduce las trazas a la décima parte
sin cambiar el código.

---

## Regla de SigNoz para nombrar variables

Verificada en <https://signoz.io/docs/operate/configuration/>:

- Toda variable de SigNoz empieza con `SIGNOZ_`.
- Los puntos del YAML se convierten en `_` y los guiones bajos originales en
  `__`.

Ejemplos reales de la doc:

```
web.enabled: true             → SIGNOZ_WEB_ENABLED=true
sqlstore.max_open_conns: 10   → SIGNOZ_SQLSTORE_MAX__OPEN__CONNS=10
```

Ojo con eso si alguna vez hay que ajustar el límite de consultas concurrentes a
ClickHouse (`SIGNOZ_QUERIER_MAX__CONCURRENT__QUERIES`, default 8): lleva doble
guion bajo.

---

## Inventario de secretos

Para una auditoría de seguridad:

| Secreto | Dónde vive | Cómo se genera |
|---|---|---|
| `POSTGRES_PASSWORD` | `.env` o gestor de Coolify | `openssl rand` |
| `SIGNOZ_USER_ROOT_PASSWORD` | `.env` o gestor de Coolify (temporal) | gestor de passwords |
| Webhook de Slack/Telegram | gestor de Coolify | del proveedor |
| Certificado TLS | gestionado por Coolify/Traefik | automático |

Ninguno va en git. El `.gitignore` del kit excluye `.env`, `*.key`, `*.pem` y
los respaldos.