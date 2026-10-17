# Kit Hefesto — Observabilidad SigNoz

Despliegue de **SigNoz** —métricas, logs, trazas, APM, alertas y tableros en una
sola herramienta— sobre Docker, para un VPS de una Pyme.

> ## Estado del kit: **kit preparado**
>
> Los archivos están escritos y varias comprobaciones se ejecutaron de verdad
> (sintaxis de scripts, defensas de seguridad, versiones, licencias). **Pero no
> hay Docker ni servidor en el entorno donde se construyó este kit.** Nunca se
> levantó una instancia. Lo que queda pendiente está en
> [`docs/07-PRUEBAS-DE-ACEPTACION.md`](docs/07-PRUEBAS-DE-ACEPTACION.md), separado
> entre lo ejecutado y lo no ejecutado.

---

## Qué problema resuelve

Hefesto ya vende **Uptime Kuma** (¿responde?) y **Umami** (¿cuánta gente entró?).
Ninguno de los dos ve el servidor ni la aplicación por dentro.

Falta el medio: por qué una consulta tardó 2,4 segundos, qué consulta fue, qué
error se repite, qué servicio está degradado. **SigNoz llena ese hueco.**

| | Uptime Kuma | Umami | SigNoz |
|---|---|---|---|
| Disponibilidad del sitio | ✅ | — | parcial |
| Tráfico web | — | ✅ | — |
| Métricas del servidor | — | — | ✅ |
| Trazas de la aplicación | — | — | ✅ |
| APM (consultas SQL, llamadas) | — | — | ✅ |
| Logs correlacionados | — | — | ✅ |

**No reemplaza a Uptime Kuma ni a Umami.** Se complementan.

---

## Lo que hay que saber antes de usarlo

### 1. La forma soportada ya no es `install.sh`

Desde la **v0.130.0**, `install.sh` y los compose de `deploy/` están
**deprecados y no se mantienen**. La forma soportada ahora es **Foundry**
(`foundryctl`), que genera los manifiestos desde un `casting.yaml`.

Fuente: <https://signoz.io/docs/install/docker/>

Este kit trae **las dos cosas**, con su propio rol declarado:

| Archivo | Qué es |
|---|---|
| `casting.yaml` | **La vía soportada por upstream.** Fuente de verdad. |
| `compose.yaml` | Copia revisada del artefacto que produce Foundry, con versiones fijadas y endurecimiento. **Marcado como no soportado por upstream.** Úsalo cuando no puedas instalar `foundryctl` (típicamente en Coolify) o quieras el compose auditable en git. |

### 2. La app y el colector versionan por separado

- App: **v0.146.0**
- Colector: **v0.144.14**

No es un error. `signoz-otel-collector:v0.146.0` **no existe** (404 en Docker
Hub). Detalle en [`VERSION.md`](VERSION.md).

### 3. La retención por defecto es 15 días, no 7

Logs y trazas **15 días**, métricas **30 días**. Verificado en la doc oficial.
Si vendes "7 días", es decisión comercial tuya, no el valor por defecto.

### 4. ClickHouse es obligatorio. Postgres es solo el metastore

- **ClickHouse** guarda la telemetría: trazas, métricas y logs. No hay
  alternativa (el schema de Foundry solo admite `clickhouse`).
- **PostgreSQL** guarda el metastore: cuentas, organizaciones, tableros y reglas
  de alerta.

**Supabase no reemplaza a ClickHouse.** Ver
[`docs/08-SERVICIOS-COMERCIALES.md`](docs/08-SERVICIOS-COMERCIALES.md).

### 5. Los puertos OTLP no tienen autenticación

**Verificado en la doc oficial:** el SigNoz self-hosted **no usa claves de
ingesta**. Quien alcance el puerto 4317 o 4318 puede escribir telemetría en la
instancia.

Este kit los deja atados a `127.0.0.1` **a propósito**. Para enviar desde
otra máquina, usa VPN o un proxy con autenticación. **No los abras a internet.**

### 6. No es multi-tenant

Una instancia es para un cliente. Los datos de todos viven en el mismo
ClickHouse. Si operas una instancia compartida, **documenta qué puede ver cada
cliente**; no prometas aislamiento.

### 7. El disco crece con la telemetría

No se autolimita. Es lo primero que se rompe en un VPS chico. Qué hacer cuando
se llena: [`docs/01-INSTALACION-DOCKER.md`](docs/01-INSTALACION-DOCKER.md).

---

## Contenido del paquete

```
hefesto-observabilidad-signoz/
├── README.md
├── casting.yaml                  vía SOPORTADA (Foundry)
├── compose.yaml                  REVISADO POR HEFESTO, no soportado por upstream
├── .env.example                  sin secretos
├── .gitignore
├── VERSION.md                    versiones, digests y de dónde salieron
├── LICENCIAS.md
├── config/                       copia literal de lo que genera foundryctl
│   ├── ingester.yaml
│   ├── opamp.yaml
│   ├── clickhouse-config.yaml
│   ├── clickhouse-keeper.yaml
│   └── clickhouse-functions.yaml
├── scripts/
│   ├── backup-signoz.sh          metastore + telemetría, manifest + SHA-256
│   └── restore-signoz.sh         valida, verifica, restaura y deja detenido
├── ejemplos/                     DEMOSTRACIÓN
│   ├── README.md
│   ├── node/                     app Node + Express instrumentada
│   ├── laravel/                  receta para Laravel
│   ├── dashboards/               guía de panel
│   └── alertas/                  guía de regla de alerta
└── docs/
    ├── 01-INSTALACION-DOCKER.md
    ├── 02-INSTALACION-COOLIFY.md
    ├── 03-VARIABLES-Y-COMO-OBTENERLAS.md
    ├── 04-PRIMERA-CUENTA-Y-USUARIOS.md
    ├── 05-RESPALDOS-Y-RESTAURACION.md
    ├── 06-ACTUALIZACIONES-Y-REVERSION.md
    ├── 07-PRUEBAS-DE-ACEPTACION.md
    ├── 08-SERVICIOS-COMERCIALES.md
    ├── 09-EXPORTACION-O-TRASPASO.md
    └── 10-LICENCIAS-Y-FUENTES.md
```

---

## Requisitos

Verificados en la documentación oficial:

- **Docker Engine 20.10+** con Compose v2.
- **Mínimo 4 GB de RAM.**
- Linux o macOS. En Windows: WSL2 con Docker nativo.
- Space en disco para la telemetría (miles de MB; crece con el uso).

Para una Pyme, la referencia práctica de Hefesto es **4 vCPU y 8 GB de RAM**.
Eso es opinión nuestra, no una cifra de upstream.

---

## Inicio rápido

```bash
cp .env.example .env
chmod 600 .env
# Edita .env: POSTGRES_PASSWORD, SIGNOZ_USER_ROOT_*

docker compose pull
docker compose up -d

curl http://localhost:8080/api/v1/health     # debe devolver {"status":"ok"}
```

Después, **borra las variables `SIGNOZ_USER_ROOT_PASSWORD` del `.env`** y
reinicia. Detalle en
[`docs/04-PRIMERA-CUENTA-Y-USUARIOS.md`](docs/04-PRIMERA-CUENTA-Y-USUARIOS.md).

Guía completa: [`docs/01-INSTALACION-DOCKER.md`](docs/01-INSTALACION-DOCKER.md).

---

## Qué es persistente y qué hay que respaldar

| Volumen | Contenido | Importancia |
|---|---|---|
| `signoz-metastore-postgres-0-data` | usuarios, **tableros**, **reglas de alerta** | **Crítico. No se regenera.** |
| `signoz-telemetrystore-0-0-data` | trazas, métricas, logs | Importante mientras la retención esté vigente |
| `signoz-telemetrykeeper-0-data` | cuórum de ClickHouse | Regenerable, mejor no tocarlo |
| `signoz-telemetrystore-user-scripts` | binario descargado | **No se respalda**: se regenera |

La idea: **la telemetría antigua es descartable; los tableros y las alertas
no.**

```bash
sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz
```

Detalle y procedimiento de restauración:
[`docs/05-RESPALDOS-Y-RESTAURACION.md`](docs/05-RESPALDOS-Y-RESTAURACION.md).

---

## Qué expone este kit

| Puerto | Servicio | ¿Publicado? |
|---|---|---|
| 8080 | UI + API | Sí (en `127.0.0.1` por defecto) |
| 4317 / 4318 | OTLP gRPC / HTTP | **Solo `127.0.0.1`** |
| 5432 | PostgreSQL | **No** |
| 9000 / 8123 | ClickHouse | **No** |
| 9181 | ClickHouse Keeper | **No** |
| 4320 | OpAMP | **No** |

> Ojo: la config de ClickHouse que genera upstream deja el usuario `default`
> **sin contraseña**. Es seguro **solo porque el puerto no se publica**. No le
> abras el 9000 "por si acaso": eso entrega la telemetría del cliente.

---

## Qué aporta upstream y qué aporta Hefesto

**Este kit es un kit de despliegue, no el código de SigNoz.** Descarga imágenes
Docker oficiales y entrega configuración. No modifica el código de SigNoz.

| Parte | Origen | Licencia |
|---|---|---|
| Aplicación, colector, ClickHouse, Postgres | Upstream | MIT / AGPL v3 / Apache 2.0 / PostgreSQL |
| `config/*.yaml` | Generado por Foundry, **copiado sin modificar** | AGPL v3 |
| `compose.yaml` | Revisión de Hefesto del artefacto de Foundry | Hefesto |
| `casting.yaml` | Escrito por Hefesto según el schema público | Hefesto |
| `scripts/`, `docs/`, `ejemplos/` | Hefesto | Hefesto |

**Lo más importante que hay que revisar antes de vender**: el colector y
Foundry están bajo **AGPL v3**, no Apache ni MIT. Detalle y lectura técnica en
[`LICENCIAS.md`](LICENCIAS.md) y
[`docs/10-LICENCIAS-Y-FUENTES.md`](docs/10-LICENCIAS-Y-FUENTES.md).

---

## Qué falta probar o configurar

Honestamente, para no perder la sorpresa:

- **Nada se ha levantado.** No hay `docker compose up` probado.
- Falta probar el ciclo completo de **respaldo → restauración** contra Docker.
- Falta confirmar si la edición Community **limita** el número de alertas o
  paneles, antes de cotizarlo.
- Falta confirmar la **matriz de roles** de la v0.146.0 y el control exacto para
  cerrar el registro de cuentas.
- Falta medir el **consumo real de RAM y disco** con telemetría de un cliente.
- La receta de **Laravel** no se ejecutó.

Todo está detallado en
[`docs/07-PRUEBAS-DE-ACEPTACION.md`](docs/07-PRUEBAS-DE-ACEPTACION.md).