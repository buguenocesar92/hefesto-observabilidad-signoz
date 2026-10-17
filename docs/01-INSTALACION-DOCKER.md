# 01 — Instalación con Docker

Instalación de SigNoz en un VPS Ubuntu o Debian limpio, por `docker compose`.

> **Estado del kit: preparado.** No hay Docker ni servidor en el entorno donde se
> construyó este kit. Ningún comando de esta guía se ejecutó contra un servidor
> real. Ver `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 0. Antes de empezar, dos decisiones

### Decisión A: ¿Foundry o el compose de Hefesto?

| | Foundry (soportado por upstream) | `compose.yaml` de Hefesto |
|---|---|---|
| Qué es | Generador de manifiestos oficial | Copia revisada del compose que produce Foundry |
| Soporte upstream | **Sí** | No |
| Requiere instalar `foundryctl` | Sí | No |
| Coolify | Vía `deployment.flavor: stack` | Directo, recurso "Docker Compose" |
| Riesgo de desviarse de upstream | Bajo | Medio: si upstream cambia algo, este archivo envejece |

**Usa Foundry** si quieres exactamente lo que upstream soporta, o si planeas
Coolify con su renderer nativo.
**Usa el compose de Hefesto** si quieres algo auditable en git, sin binarios
extra en el servidor, y estás conforme en mantenerlo a mano cuando upstream
cambie.

La guía cubre las dos.

### Decisión B: requisitos del servidor

Mínimo oficial: **4 GB de RAM**, Docker Engine 20.10+ con Compose v2, Linux o
macOS (en Windows, WSL2 con Docker nativo).
Fuente: <https://signoz.io/docs/install/docker/>

Para una Pyme, la referencia práctica es **4 vCPU y 8 GB de RAM**. Eso es
opinión de Hefesto, no una cifra de upstream. Ver la sección de consumo de
recursos más abajo.

---

## 1. Preparar el servidor

```bash
# Actualizar
sudo apt update && sudo apt upgrade -y

# Docker (repositorio oficial de Docker para Ubuntu/Debian)
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

Verificar:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

## 2. Traer el kit

```bash
sudo mkdir -p /opt/signoz
sudo chown "$USER":"$USER" /opt/signoz
cd /opt/signoz

# Copiar aquí el contenido del kit (git clone, rsync o copia manual)
```

## 3. Crear el `.env`

```bash
cp .env.example .env
chmod 600 .env

# Los scripts también necesitan permiso de ejecución
chmod +x scripts/backup-signoz.sh scripts/restore-signoz.sh

# Generar la contraseña del metastore
openssl rand -base64 24 | tr -d '/+=' | cut -c1-32
```

Editar `.env` y poner:

```dotenv
POSTGRES_PASSWORD=<la cadena que acabas de generar>
SIGNOZ_USER_ROOT_ENABLED=true
SIGNOZ_USER_ROOT_EMAIL=admin@tucliente.cl
SIGNOZ_USER_ROOT_PASSWORD=<contraseña fuerte del administrador>
SIGNOZ_USER_ROOT_ORG_NAME=<nombre del cliente>
SIGNOZ_BIND_ADDRESS=127.0.0.1
```

`SIGNOZ_BIND_ADDRESS=127.0.0.1` deja la UI solo en el servidor. En un VPS sin
proxy delante, cámbialo a `0.0.0.0` y pon un firewall y HTTPS. Ver el punto
"Exposición de la UI" más abajo.

## 4. Levantar

### Opción A — con el compose de Hefesto

```bash
docker compose pull
docker compose up -d
```

### Opción B — con Foundry (vía soportada por upstream)

```bash
# Instalar foundryctl según la doc de upstream
curl -fsSL https://raw.githubusercontent.com/SigNoz/foundry/main/foundry.sh | bash

foundryctl cast --file casting.yaml --output-dir ./pours
docker compose -f pours/deployment/compose.yaml up -d
```

`casting.yaml` ya trae las versiones fijadas y el bloque `patches` con el
endurecimiento (OTLP atado a loopback y dependencias de arranque).

## 5. Verificar

```bash
# Estado de los contenedores
docker compose ps

# Health del backend. Debe devolver {"status":"ok"}
curl http://localhost:8080/api/v1/health
```

El healthcheck del contenedor `signoz-signoz-0` es exactamente ese endpoint
(`wget --spider -q http://localhost:8080/api/v1/health`), tomado del artefacto
que produce Foundry.

El primer arranque tarda: ClickHouse tiene que correr sus migraciones de esquema
(job `signoz-telemetrystore-migrator`) y el binario `histogram-quantile` se
descarga desde GitHub. Dale unos minutos.

### Si quieres ver el avance

```bash
docker compose logs -f signoz-telemetrystore-migrator
docker compose logs -f signoz-telemetrystore-clickhouse-user-scripts
docker compose logs -f signoz-signoz-0
```

## 6. Entrar por primera vez

Con las variables de `SIGNOZ_USER_ROOT_*`, entra en `http://<ip>:8080` con el
correo y la contraseña que configuraste. Después **borra esas variables del
`.env`** y reinicia, para que la contraseña no quede en el servidor.

Procedimiento completo en `04-PRIMERA-CUENTA-Y-USUARIOS.md`.

---

## Exposición de la UI: qué hacer según el caso

| Situación | Configuración |
|---|---|
| Hay un proxy inverso (Traefik de Coolify, nginx, Caddy) | `SIGNOZ_BIND_ADDRESS=127.0.0.1`. El proxy termina TLS y expone. **Es lo recomendado.** |
| Acceso directo por IP, sin proxy | `SIGNOZ_BIND_ADDRESS=0.0.0.0` **y** HTTPS. Un SigNoz en HTTP plano por internet expone datos del cliente. |
| desarrollo local | `127.0.0.1` y un túnel SSH. |

---

## Consumo de recursos: la parte que hay que explicar al cliente

La RAM y el disco **crecen con la telemetría**. No es un programa que se instala
y queda ahí.

- **RAM**: los 4 GB son el piso declarado. Entre 4 y 8 GB el sistema va bien
  mientras la telemetría sea moderada.
- **Disco**: es donde esto se rompe. ClickHouse guarda trazas, métricas y logs
  hasta que su retención vence. El volumen `signoz-telemetrystore-0-0-data` es
  el que crece.

Qué hacer cuando el disco se llena, en orden:

1. **Bajar la retención** (Settings → Workspace → Retention Controls). Es la
   palanca más rápida.
2. **Dejar de enviar logs a SigNoz** si el cliente ya tiene otro sistema de
   logs. Los logs suelen ser la mayor parte del volumen.
3. **Muestrear las trazas** en la app (sampling). Menos trazas, menos detalle.
4. **Mover ClickHouse a un disco más grande o a un servidor aparte.** Requiere
   planificación; no es un cambio de configuración.
5. Última instancia: **reducir el período de retención** a lo que el cliente
   realmente mira. Diez días de datos que nadie revisa es solo disco ocupado.

**Aviso honesto al cliente:** no puedo darte la cifra exacta de "cuánto disco
gasta por cliente" sin medirlo en tu servidor. Depende de cuántas apps, qué
cantidad de requests y si mandas logs o no. Instala, mide una semana con datos
reales y despues ajusta. Preferimos decir "hay que medirlo" que inventar un
número.

---

## Problemas frecuentes

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La app reinicia en bucle | RAM insuficiente | Revisa `docker stats`. Con 4 GB justos queda poco margen. |
| `ResourceExhausted` en la ingesta | Payload OTLP muy grande | Sube `max_recv_msg_size_mib` en el receptor `grpc` del colector. |
| El navegador no recibe telemetría | CORS | Por defecto el collector solo permite `http://localhost:8080` y `:8081`. Agrega tu origen en `allowed_origins`. |
| El contenedor `user-scripts` falla | Sin salida a GitHub | Verifica conectividad. Se reintenta con `on-failure`. |
| No llegan datos | OTLP atado a `127.0.0.1` y la app está en otra máquina | Ver la sección de puertos OTLP en `08-SERVICIOS-COMERCIALES.md`. |