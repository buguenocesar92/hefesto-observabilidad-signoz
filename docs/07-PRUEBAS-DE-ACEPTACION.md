# 07 — Pruebas de aceptación

Este documento separa **lo que realmente se ejecutó** de **lo que quedó
pendiente**. No hay pruebas simuladas presentadas como reales.

> ## Estado del kit: **kit preparado**
>
> En el entorno donde se construyó este kit **no hay Docker, ni servidor, ni
> una instancia de SigNoz corriendo**. Todo lo que aparece abajo como
> "ejecutado" se ejecutó de verdad, pero ninguna pruebaRequiere Docker.

---

## A. Realmente ejecutado en este entorno

### A.1 — Documentación y versiones (verificado contra fuentes)

| Qué | Cómo se verificó | Resultado |
|---|---|---|
| Versión estable más reciente de SigNoz | `GET api.github.com/repos/SigNoz/signoz/releases/latest` | **v0.146.0**, publicada 2026-10-14 |
| Digest de `signoz/signoz:v0.146.0` | API de Docker Hub | manifest list `sha256:cd3ca695…ab14ca`; amd64 `sha256:27cec42d…da7746`; arm64 `sha256:1a9295df…e2dd1` |
| El colector **no** comparte versión con la app | API de Docker Hub | Último tag del colector: **v0.144.14** (2026-10-13). `v0.146.0` da **404**. |
| Licencia de la app | Descarga de `LICENSE` en `v0.146.0` | MIT Expat, **excepto** `ee/` y `cmd/enterprise/` |
| Licencia de `ee/` | Descarga de `ee/LICENSE` en `v0.146.0` | SigNoz Enterprise License: uso en producción con suscripción |
| Licencia del colector | Descarga de `LICENSE` en `v0.144.14` | **GNU AGPL v3** |
| Licencia de Foundry | Descarga de `LICENSE` en `main` | **GNU AGPL v3** |
| Licencia de ClickHouse | Descarga de `LICENSE` | Apache 2.0 |
| Licencia de PostgreSQL | Descarga de `COPYRIGHT` | PostgreSQL License |
| Deprecación de `install.sh` desde v0.130.0 | Doc oficial de instalación | Confirmado; Foundry es la vía soportada |
| Retención por defecto | Doc oficial de retención | **15 días** logs y trazas, **30 días** métricas |
| Campos del casting de Foundry | Descarga de `casting.schema.json` | `V1Alpha1MoldingSpec` con `image`, `version`, `env`, `enabled` |
| `image` acepta digest | `casting.schema.json`, patrón del campo | Sí: `repo:tag` y `repo@sha256:<64 hex>` |
| Enums de plataforma y flavor | `casting.schema.json` | `platform: coolify`, `flavor: stack`, `compose`, etc. |
| `telemetrystore.kind` | `casting.schema.json` | **Solo `clickhouse`**. No hay alternativa. |
| Compose real que produce Foundry | Descarga del artefacto versionado | Obtenido y usado como base del `compose.yaml` |
| Archivos de config que genera Foundry | Descarga de `pours/deployment/**` | Los 5 archivos, copiados a `config/` |
| Healthchecks | Leídos del artefacto de Foundry | 4 healthchecks reales; el colector **no** tiene ninguno upstream |
| Paquetes OpenTelemetry (Node) | Registro de npm | `sdk-node` 0.223.0, `auto-instrumentations-node` 0.81.2, `api` 1.9.1 |
| Paquete OpenTelemetry (Laravel) | Packagist | `open-telemetry-auto-laravel` 1.10.0, PHP ^8.1, Laravel ^10–^13 |

### A.2 — Comprobaciones ejecutadas sobre los archivos del kit

Estas sí se corrieron, con herramientas reales:

| Prueba | Herramienta | Resultado |
|---|---|---|
| Sintaxis de `backup-signoz.sh` | `bash -n` (GNU bash 5.3.15) | **OK** |
| Sintaxis de `restore-signoz.sh` | `bash -n` | **OK** |
| `--help` en ambos scripts | ejecución real | exit 0, salida correcta |
| Sin argumentos | ejecución real | Muestra uso y sale con 1. Correcto |
| Backup rechaza ruta relativa | ejecución real | **Rechazado** |
| Backup rechaza `..` | ejecución real | **Rechazado** |
| Backup rechaza destino dentro del kit | ejecución real | **Rechazado**, antes de tocar Docker |
| Restore rechaza directorio inexistente | ejecución real | **Rechazado** |
| Restore rechaza `..` | ejecución real | **Rechazado** |
| Restore rechaza respaldo sin `.COMPLETO` | ejecución real | **Rechazado**, antes de tocar Docker |
| Restore rechaza manifiesto con `../../../etc/passwd` | ejecución real | **Rechazado** |
| Restore rechaza manifiesto con ruta absoluta | ejecución real | **Rechazado** |
| Restore rechaza manifiesto con archivo inexistente | ejecución real | **Rechazado** |
| Restore rechaza SHA-256 malformado | ejecución real | **Rechazado** |
| Sintaxis de `otel.js` | `node --check` (Node 24.21.0) | **OK** |
| Sintaxis de `server.js` | `node --check` | **OK** |
| `package.json` es JSON válido | parser JSON | **OK** |
| Los 7 archivos YAML parsean | PyYAML `safe_load` | **OK**: `compose.yaml`, `casting.yaml` y los 5 de `config/` |
| Revisión semántica del `compose.yaml` | script de comprobación propio | **7 servicios**, **4 volúmenes**, 4 healthchecks, **ninguna imagen `latest`**, **ningún puerto interno de base de datos publicado** (5432/9000/8123/9181/4320), OTLP atado a `127.0.0.1`, healthcheck de la app apuntando a `/api/v1/health` |

> Sobre la revisión semántica: el puerto 8080 aparece como
> `${SIGNOZ_BIND_ADDRESS:-127.0.0.1}:8080:8080`. Es una variable parametrizada a
> propósito, con loopback por defecto, para poder exponer la UI detrás de un
> proxy. No es un puerto de base de datos y no queda abierto por omisión.

> ### Un bug real que encontró una prueba
>
> La validación del manifiesto usaba `while … done < <(grep …)`. Con process
> substitution el bucle corre en un **subshell**: `exit 1` terminaba el subshell,
> **no el script**, y la restauración seguía adelante con un manifiesto
> manipulado. La prueba con `../../../etc/passwd` lo detectó. Se corrigió a
> redirección de archivo (`done < archivo`) y se volvió a probar: ahora rechaza.
>
> Sin esa prueba, el script habría pasado la revisión visual y fallado en
> producción.

---

## B. Pendiente — requiere Docker o un servidor

Nada de esto se ejecutó. **No lo presentes como probado.**

### B.1 — Despliegue

- [ ] `docker compose config` valida el `compose.yaml`.
- [ ] `docker compose up -d` levanta los seis servicios.
- [ ] Los cuatro healthchecks **pasan**: Postgres (`pg_isready`), ClickHouse
      (`/ping`), Keeper (`clickhouse-keeper-client ls`) y SigNoz
      (`/api/v1/health`).
- [ ] El job `signoz-telemetrystore-migrator` termina en exit 0.
- [ ] `signoz-telemetrystore-clickhouse-user-scripts` descarga el binario.
- [ ] **ClickHouse (9000/8123), Keeper (9181) y Postgres (5432) no son accesibles
      desde el host.** Verificar con `ss -tlnp` o desde otra máquina.
- [ ] `curl http://localhost:8080/api/v1/health` devuelve `{"status":"ok"}`.

### B.2 — Foundry

- [ ] `foundryctl cast --file casting.yaml --output-dir ./pours` genera el
      artefacto sin errores.
- [ ] El `env:` del casting (variables del root user) se propaga al compose
      generado. **Esto no lo pude verificar**: el schema permite el campo
      `env`, pero no comprobé que `foundryctl` lo volque en el contenedor.
- [ ] Los parches del bloque `patches` aplican sin error y las rutas JSON
      Pointer son correctas.
- [ ] El compose generado y el `compose.yaml` de Hefesto coinciden en
      estructura.

### B.3 — Usuarios y seguridad

- [ ] El root user se crea en el arranque con las variables de entorno.
- [ ] Se puede entrar con ese correo y contraseña.
- [ ] Tras borrar las variables y reiniciar, el root user **sigue** existiendo.
- [ ] Nombre exacto de la pantalla para **cerrar el registro** de cuentas
      nuevas, y si la edición Community permite desactivarlo globalmente.
- [ ] **Matriz de roles** de la v0.146.0: qué puede hacer un miembro frente a
      un administrador. No verificada.

### B.4 — Telemetría

- [ ] La app de `ejemplos/node/` manda trazas que aparecen en la UI.
- [ ] Llegan métricas (`demo_latencia_ms`, `demo_peticiones_total`).
- [ ] Llegan logs (`[demo]`).
- [ ] El CORS del receptor OTLP/HTTP bloquea orígenes no permitidos.

### B.5 — Retención y límites

- [ ] La retención por defecto aparece como 15/15/30 días en la UI.
- [ ] Cambiar la retención afecta **solo** a datos nuevos (confirmar en la UI).
- [ ] **¿La edición Community impone límites al número de alertas o paneles?**
      No verificado. Confirmarlo antes de vender "N alertas" en una propuesta.
- [ ] Consumo real de RAM y disco con telemetría de un cliente real. **No hay
      cifra oficial para el despliegue de un nodo**: hay que medir.

### B.6 — Respaldo y restauración

- [ ] `backup-signoz.sh` completa las 5 fases y escribe `.COMPLETO`.
- [ ] `manifest.sha256` verifica con `sha256sum -c`.
- [ ] `restore-signoz.sh` restaura sobre una instancia vacía.
- [ ] Los tableros y las alertas sobreviven al ciclo.
- [ ] Restore **se niega** sobre un destino con datos (probado con Docker real).
- [ ] `--force` exige la confirmación escrita.

### B.7 — Coolify

- [ ] Despliegue como recurso Docker Compose.
- [ ] Proxy y TLS funcionando.
- [ ] Los cuatro volúmenes quedan persistentes.
- [ ] La vía Foundry nativa (`platform: coolify`, `flavor: stack`) **no se
      probó**: queda en `B.2`.

### B.8 — Documentación pendiente de confirmar

- [ ] El puerto **8000** para MCP: la doc oficial lo menciona, pero este kit
      **no lo habilita** ni lo publica. Confirmar si hace falta para algo.
- [ ] Variables del cliente en Laravel (`ejemplos/laravel/`): que el paquete
      1.10.0 las lea todas.
- [ ] API de recursos de OpenTelemetry en JS (`resourceFromAttributes` en
      `@opentelemetry/resources` 2.x): firma exacta en la versión instalada.

---

## C. Checklist de aceptación para el despliegue del cliente

Esto es lo que hay que hacer **en el servidor**, antes de entregar. Es la lista
que se le pide al cliente o la que Hefesto ejecuta antes de dar por cerrado un
servicio.

### Antes del primer arranque

- [ ] `.env` existe, tiene permisos `600` y no está en git.
- [ ] `POSTGRES_PASSWORD` generada con `openssl rand`, no una palabra inventada.
- [ ] `SIGNOZ_USER_ROOT_*` configuradas.
- [ ] Versiones fijadas en el `compose.yaml` (sin `latest`).

### Después del arranque

- [ ] `curl http://localhost:8080/api/v1/health` → `{"status":"ok"}`.
- [ ] `docker compose ps` muestra todo `healthy` (o `exited 0` los jobs).
- [ ] Solo el puerto 8080 está publicado. ClickHouse, Keeper, Postgres y OTLP
      **no** lo están.

### Antes de entregar al cliente

- [ ] Variables `SIGNOZ_USER_ROOT_PASSWORD` borradas del `.env`.
- [ ] HTTPS funcionando.
- [ ] Respaldo hecho **y verificado**.
- [ ] Al menos una alerta creada y probada (dispararla y ver que llega).
- [ ] Al menos un panel creado.
- [ ] Documentado al cliente qué puede ver cada usuario.
- [ ] Documentado al cliente que el consumo de disco crece con la telemetría.