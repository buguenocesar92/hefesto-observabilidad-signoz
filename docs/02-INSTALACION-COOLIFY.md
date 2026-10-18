# 02 — Instalación en Coolify

Despliegue de SigNoz como recurso **Docker Compose** en Coolify.

> **Estado del kit: preparado.** No se ejecutó en un servidor Coolify. Todo lo
> de acá viene de la documentación oficial de SigNoz y del compose del kit, no de
> una instalación probada. Ver `07-PRUEBAS-DE-ACEPTACION.md`.

---

## Dos formas de hacerlo en Coolify

| Vía | Cómo | Cuándo |
|---|---|---|
| **A — Recurso Docker Compose** | Subes el `compose.yaml` como recurso | Lo normal para este kit. Simple y auditable. |
| **B — Foundry nativo** | `casting.yaml` con `platform: coolify` y `deployment.flavor: stack` | Si quieres el renderer oficial de Foundry para Coolify. Requiere que Coolify pueda ejecutar `foundryctl`. |

El `casting.yaml` de este kit trae:

```yaml
deployment:
  flavor: stack
platform: coolify
```

Los valores `platform` y `flavor` están verificados contra el schema de Foundry
(`V1Alpha1Platform` acepta `coolify`; `V1Alpha1Flavor` acepta `stack`).

**Honestidad:** la vía B la dejé lista en el schema pero **no la probé**. El
comando exacto para pasar el casting por el pipeline de Coolify depende de cómo
Coolify lo integre en la versión que uses. Antes de venderla, pruébala. La vía A
sí es un flujo estándar de Coolify.

---

## Vía A — Recurso Docker Compose (la recomendada)

### 1. Subir el kit al servidor

En Coolify: **Projects → tu proyecto → New Resource → Docker Compose**, y
apunta el repositorio git donde tengas el kit.

Si el kit no está en git todavía:

```bash
cd /ruta/del/kit
git init
git add .
git commit -m "Kit SigNoz Hefesto v0.146.0"
```

El `.gitignore` del kit ya excluye `.env`, respaldos y claves.

### 2. Configurar el dominio

En el recurso, **Domains**:

- Dominio: `observabilidad.tucliente.cl`
- Puerto: `8080`

Coolify genera el proxy inverso (Traefik) y pide el certificado TLS
automáticamente si el DNS ya apunta al servidor.

> **Sobre `SIGNOZ_BIND_ADDRESS`:** el `compose.yaml` de este kit pública la UI en
> `127.0.0.1:8080` por defecto. Con el proxy de Coolify, **déjalo en `127.0.0.1`**:
> el proxy y el contenedor comparten red de Docker, así que alcanza. Si lo pones
> en `0.0.0.0`, la UI queda además accesible por IP sin TLS.

**Healthcheck y dominio:** SigNoz responde en `/api/v1/health`. No necesita una
ruta especial de base (no hay subpath). Coolify espera que el contenedor reporte
`healthy`, y el healthcheck del compose hace exactamente eso.

### 3. Variables de entorno

En el recurso, **Environment Variables**:

| Variable | Valor | Secreto |
|---|---|---|
| `POSTGRES_PASSWORD` | cadena generada | **Sí** |
| `SIGNOZ_USER_ROOT_ENABLED` | `true` (solo en el primer despliegue) | No |
| `SIGNOZ_USER_ROOT_EMAIL` | `admin@tucliente.cl` | No |
| `SIGNOZ_USER_ROOT_PASSWORD` | contraseña fuerte | **Sí** |
| `SIGNOZ_USER_ROOT_ORG_NAME` | nombre del cliente | No |
| `SIGNOZ_BIND_ADDRESS` | `127.0.0.1` | No |

Coolify marca las variables como secretas y las cifra en su base de datos.
Marcalas todas las que son credenciales.

### 4. Volúmenes

El compose declara cuatro volúmenes nombrados:

| Volumen | Qué guarda | Qué pasa si lo pierdes |
|---|---|---|
| `signoz-metastore-postgres-0-data` | usuarios, organizaciones, tableros, alertas | **Se pierde la configuración del cliente.** |
| `signoz-telemetrystore-0-0-data` | telemetría (trazas, métricas, logs) | Se pierde el historial, no la configuración. |
| `signoz-telemetrykeeper-0-data` | estado del cuórum | Se regenera, pero mejor no tocarlo. |
| `signoz-telemetrystore-user-scripts` | binario descargado | Se regenera solo. |

En **Advanced → Volumes**, revisa que Coolify haya creado los cuatro y que no
sean efímeros. Un volumen no persistente en un VPS es perder la instancia en la
primera reinstalación.

Los scripts de respaldo de este kit asumen los nombres de volumen tal como
están declarados. Si Coolify les pone prefijo, ajusta las variables
`VOL_*` de `scripts/backup-signoz.sh`.

### 5. Desplegar y verificar

```bash
# Desde el servidor, por SSH
cd /data/coolify/<proyecto>/<recurso>
docker compose ps
curl -s http://127.0.0.1:8080/api/v1/health
```

Después: `https://observabilidad.tucliente.cl`.

### 6. Después del primer despliegue

Borra `SIGNOZ_USER_ROOT_ENABLED`, `SIGNOZ_USER_ROOT_EMAIL` y
`SIGNOZ_USER_ROOT_PASSWORD` de las variables de Coolify y vuelve a desplegar. La
contraseña del administrador queda en el gestor de Coolify si la dejas puesta.

Detalle en `04-PRIMERA-CUENTA-Y-USUARIOS.md`.

---

## Puertos y OTLP en Coolify

El `compose.yaml` deja 4317 y 4318 atados a `127.0.0.1`. **No los publiques
como puertos del recurso en Coolify.**

Si una app en otro servidor tiene que mandar telemetría, las opciones
ordenadas de menos a más riesgo:

1. **VPN (WireGuard) entre los servidores.** La app manda a la IP privada de
   WireGuard. Ningún puerto nuevo expuesto.
2. **Proxy inverso con autenticación** delante de OTLP, exponiendo solo 4318
   (HTTP) por HTTPS con mTLS o basic auth.
3. **SSH tunnel**: `ssh -L 4317:127.0.0.1:4317 usuario@servidor-signoz`.

Lo que **no** es aceptable: abrir 4317 al mundo "porque es más fácil". SigNoz
self-hosted **no pide clave de ingesta** (verificado en la doc oficial), así que
cualquiera que llegue al puerto escribe telemetría en la instancia de tu
cliente. Detalle en `08-SERVICIOS-COMERCIALES.md`.

---

## Actualizar en Coolify

1. Respaldo primero: `./scripts/backup-signoz.sh --destino /var/backups/signoz`.
2. Cambia la versión en el `compose.yaml` (y en `casting.yaml`).
3. Redeploy desde Coolify.
4. Revisa los logs del job `signoz-telemetrystore-migrator`: es el que aplica
   migraciones de esquema, y **no se revierten solas**.

Detalle en `06-ACTUALIZACIONES-Y-REVERSION.md`.

---

## Si algo no funciona

| Síntoma | Qué revisar |
|---|---|
| El dominio no carga | El proxy de Coolify no alcanza el puerto 8080. Revisa que el contenedor esté `healthy` y que `SIGNOZ_BIND_ADDRESS` no bloquee al proxy. |
| "502 Bad Gateway" | Contenedor caído o aún arrancando (ClickHouse tarda). Espera y revisa `docker compose logs`. |
| Los datos desaparecen entre despliegues | Volumen no persistente o nombre cambiado. Verifica en Advanced → Volumes. |
| El despliegue se reinicia en bucle | RAM insuficiente. SigNoz necesita mínimo 4 GB. |