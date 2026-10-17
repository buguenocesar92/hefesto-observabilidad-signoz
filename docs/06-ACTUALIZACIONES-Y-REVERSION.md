# 06 — Actualizaciones y reversión

Cómo actualizar SigNoz con la versión fijada, cómo volver atrás y qué
migraciones no se pueden deshacer.

---

## Antes de cualquier actualización

```bash
# 1. Respaldo. Siempre. Sin excepción.
sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz \
     --etiqueta antes-de-actualizar

# 2. Anota las versiones actuales
docker compose config --images | sort -u
```

Si el respaldo no terminó bien (no hay `.COMPLETO`), **no sigas**.

## Cómo actualizar

### 1. Revisa el changelog de la versión destino

<https://github.com/SigNoz/signoz/releases>

Busca en particular: notas sobre ClickHouse, cambios de esquema y cualquier
mención de migración.

### 2. Cambia la versión

En `compose.yaml`, **las dos** imágenes de SigNoz. Ojo con esto: **la app y el
colector versionan por separado**.

```yaml
# signoz-signoz-0
image: signoz/signoz:v0.146.0          # → v0.147.0

# ingester
image: signoz/signoz-otel-collector:v0.144.14   # → el último tag que exista
```

No asumas que el tag del colector coincide con el de la app. Consulta Docker
Hub:

```bash
curl -s "https://hub.docker.com/v2/repositories/signoz/signoz-otel-collector/tags?page_size=10&ordering=last_updated" \
  | grep -o '"name":"[^"]*"' | head
```

Si usas Foundry, cambia también `casting.yaml`.

### 3. Descarga las imágenes antes de cortar servicio

```bash
docker compose pull
```

Mejor que descubrir que el registro felló **después** de tirar el servicio
abajo.

### 4. Levanta

```bash
docker compose up -d
docker compose ps
```

### 5. Mira las migraciones

El servicio `signoz-telemetrystore-migrator` es el que aplica las migraciones de
esquema en ClickHouse. Son el punto crítico del upgrade:

```bash
docker compose logs -f signoz-telemetrystore-migrator
```

Debe terminar **exitoso**. Un migrator que falla y reintenta (`on-failure`) es
normal un par de veces; un migrador que se queda en bucle, no.

### 6. Verifica

```bash
curl -s http://127.0.0.1:8080/api/v1/health     # {"status":"ok"}
```

Y en la UI: entra, revisa que los tableros estén, que las alertas estén y que
lleguen datos nuevos.

## Volver atrás (reversión)

### El caso fácil: el problema es de configuración, no de esquema

Si no hubo migración de esquema, revertir es cambiar la etiqueta a la versión
anterior y `up -d` de nuevo. Los volúmenes se quedan como están.

### El caso difícil: hubo migración de esquema

**Las migraciones de ClickHouse las aplica el job al arrancar y no se deshacen
solas.** No hay un "downgrade" que deshaga el esquema.

Si el esquema ya migró y vuelves a una versión antigua de SigNoz, esa versión
puede no entender las tablas nuevas. El resultado típico es una instancia que
levanta pero con errores en las consultas.

**La única vuelta atrás fiable es restaurar el respaldo:**

```bash
docker compose down
# Borrar los volúmenes para que el restore parta de cero
docker volume rm signoz-metastore-postgres-0-data
docker volume rm signoz-telemetrystore-0-0-data
docker volume rm signoz-telemetrykeeper-0-data

sudo ./scripts/restore-signoz.sh --respaldo /var/backups/signoz/signoz-<fecha>-antes-de-actualizar
```

Por eso el respaldo del paso 0 no es opcional: **es tu único camino de vuelta.**

> **Punto de atención:** al restaurar sobre volúmenes que acabas de borrar, el
> script no debería pedir `--force` (están vacíos). Si lo pide, es que algo no
> quedó vacío: revisa antes de confirmar.

## Reglas prácticas

1. **Una versión a la vez.** No saltes varias versiones de golpe.
2. **Actualiza en horario Ticket.** Si el migrador falla, tienes tiempo de
   diagnosticar.
3. **Anota lo que cambiaste.** El changelog de SigNoz cambia entre versiones.
4. **Verifica los tableros después de cada upgrade.** Es la forma más rápida de
   detectar un problema de esquema.
5. **No actualices la app y el colector a la vez** en el mismo paso si puedes
   evitarlo. Si algo falla, quieres saber cuál de los dos fue.

## Cuándo NO actualizar

- El cliente tiene una demo o una campaña esa semana.
- La retención es alta (15 días) y ya no cabe el respaldo en otro disco.
- El servidor está justo de RAM y el upgrade viene con un arranque más pesado.

Esperar dos semanas no cuesta nada. Un upgrade fallado el viernes a las 18:00
sí.

## Resumen de reversión

| Situación | Reversión |
|---|---|
| Config mal puesta, sin migración | Cambiar etiqueta + `up -d` |
| Migración aplicada, la app no funciona | **Restaurar respaldo.** No hay downgrade de esquema. |
| La app funciona pero algo cambió de comportamiento | Casi siempre es versión de colector, no de app. Prueba volver solo el colector. |
| Falla el `user-scripts` (descarga de GitHub) | No afecta los datos. Reintenta. |