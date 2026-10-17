# 05 — Respaldos y restauración

Qué se guarda, qué se puede perder, cómo sacar una copia coherente y cómo
restaurarla sin romper nada.

---

## La idea central

En SigNoz hay **dos cosas muy distintas** guardadas:

| | Qué es | ¿Se puede regenerar? |
|---|---|---|
| **Metastore (Postgres)** | cuentas, organizaciones, **tableros**, **reglas de alerta**, preferencias | **NO.** Si se pierde, se rehace a mano. Semanas de trabajo. |
| **Telemetría (ClickHouse)** | trazas, métricas, logs | Sí, en el sentido de que vuelve a llenarse sola. Lo viejo no. |

**La conclusión práctica: el respaldo que importa es el del metastore.**

Si el cliente pierde los tableros, perdió las alertas que le cobramos
configurar. Si pierde tres días de logs, es una molestia menor.

No porque se pueda descartar la telemetría a la ligera —si el cliente pregunta
por qué un servicio falló el martes, esa traza vale dinero—, sino porque
regenerarla es cuestión de esperar, mientras que el metastore no se regenera
nunca.

---

## 1. Qué es persistente

Estos cuatro volúmenes,, tal como los declara el `compose.yaml`:

| Volumen | Ruta dentro del contenedor | Contenido |
|---|---|---|
| `signoz-metastore-postgres-0-data` | `/var/lib/postgresql/data` | Base de datos del metastore. **Crítico.** |
| `signoz-telemetrystore-0-0-data` | `/var/lib/clickhouse` | Trazas, métricas y logs. |
| `signoz-telemetrykeeper-0-data` | `/var/lib/clickhouse-keeper` | Estado del cuórum de ClickHouse. |
| `signoz-telemetrystore-user-scripts` | `/var/lib/clickhouse/user_scripts` | Binario `histogram-quantile`. |

## 2. Qué NO se respalda

| Elemento | Por qué no |
|---|---|
| `signoz-telemetrystore-user-scripts` | Es un binario que se descarga de GitHub en cada arranque. Se regenera solo. |
| `.env` | Contiene secretos. **No van en el respaldo**: guárdalos en un gestor de passwords aparte. |
| `config/` | Está en git, junto al kit. |
| Telemetría ya vencida | Al superar su TTL, ClickHouse la **borra de forma definitiva**. No hay nada que respaldar. |

## 3. Qué secretos hay que conservar aparte

Si pierdes estos, el respaldo está intacto pero **no lo puedes restaurar**:

| Secreto | Para qué |
|---|---|
| `POSTGRES_PASSWORD` | Conectar al metastore. Sin él, `pg_restore` no entra. |
| `SIGNOZ_USER_ROOT_PASSWORD` | Entrar como administrador. Sin él, se puede recuperar cambiando las variables y reiniciando (el root user no se edita desde la UI). |

Guárdalos en el gestor de Coolify, en Bitwarden, o donde corresponda. **Nunca
en el mismo disco que el respaldo.**

## 4. Cómo sacar una copia coherente

Coherente significa: no copiamos una base mientras alguien escribe en ella.

`scripts/backup-signoz.sh` lo resuelve en fases:

1. **Detiene la app y el colector.** Son los que escriben. ClickHouse y Postgres
   siguen arriba.
2. **`pg_dump` del metastore.** Con Postgres corriendo: el dump sale
   consistente por MVCC, sin bloquear la instancia.
3. **Detiene ClickHouse.** Con ClickHouse parado, se copia el volumen en frío
   con `tar`. Sin parar el motor, la copia sería un desastre.
4. **Copia el volumen de Keeper.** Pequeño, se hace por completitud.
5. **Calcula SHA-256** de cada artefacto y los verifica con `sha256sum -c`.
6. **Escribe `.COMPLETO`** al final. Solo entonces.

### El orden importa

Si copiaras el volumen de ClickHouse **con el motor corriendo**, podrías tener
archivos partially written. Por eso el script lo detiene. Es la diferencia entre
un respaldo usable y uno que parece estar bien y no lo está.

### Qué produce

```
signoz-<fecha-utc>-<etiqueta>/
├── postgres-metastore.dump        pg_dump formato custom (comprimido)
├── clickhouse-telemetria.tar.gz   volumen /var/lib/clickhouse
├── clickhouse-keeper.tar.gz       volumen /var/lib/clickhouse-keeper
├── MANIFIESTO.txt                 qué es cada cosa y qué no se incluyó
├── manifest.sha256                SHA-256 de cada artefacto
└── .COMPLETO                      marca de que terminó bien
```

### `.COMPLETO` es la garantía

Si el respaldo falla a mitad, el directorio **no** tiene `.COMPLETO`, y
`restore-signoz.sh` se niega a restaurarlo. No se marca completo antes de
terminar: nunca.

## 5. Cómo usarlo

```bash
# Respaldar
sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz

# Con etiqueta para saber por qué
sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz \
     --etiqueta antes-de-actualizar-v0.146

# Verificar un respaldo viejo a mano
cd /var/backups/signoz/signoz-20261016T120000Z-pre-actualizar
sha256sum -c manifest.sha256
```

**El script deja la instancia DETENIDA al terminar.** Es deliberado: evita que
se escriba entre el respaldo y la siguiente operación. Levántala con:

```bash
docker compose -f compose.yaml up -d
```

### Automatizar

```bash
# A las 3 de la mañana, todos los días
0 3 * * * /opt/signoz/scripts/backup-signoz.sh --destino /var/backups/signoz
```

Un respaldo que depende de que alguien se acuerde no es un respaldo.

## 6. Restauración

```bash
sudo ./scripts/restore-signoz.sh \
     --respaldo /var/backups/signoz/signoz-20261016T120000Z-pre-actualizar
```

El script hace, en orden:

1. **Valida rutas**: rechaza `..`, rutas relativas, symlinks y respaldos dentro
   del propio kit.
2. **Verifica `.COMPLETO`**: un respaldo a medias no se restaura.
3. **Revisa las rutas del manifiesto**: cada nombre debe ser un archivo simple
   dentro de la carpeta. Nada de `../../../etc/passwd` ni de rutas absolutas.
   Esto se valida **contra path traversal** antes de extraer nada.
4. **Verifica los SHA-256.** Si algo no cuadra, no toca nada.
5. **Comprueba si el destino está ocupado.** Si hay datos, **se niega**, salvo
   `--force` explícito más una confirmación escrita.
6. **Levanta Postgres vacío y restaura el metastore** con `pg_restore`.
7. **Restaura los volúmenes** de telemetría y Keeper.
8. **Deja todo DETENIDO** para que alguien revise.

### Las reglas duras

| Regla | Por qué |
|---|---|
| Nunca `DROP` | Un `pg_restore` con `--clean` sobre la base equivocada destruye la configuración del cliente. Este script **no** usa `--clean`. |
| Nunca sobrescribir sin permiso | Destino ocupado = el script se detiene, salvo `--force`. |
| No extraer sobre rutas arbitrarias | Un `tar` sobre una ruta calculada desde un manifiesto manipulado puede escribir donde sea. Se valida antes. |
| Terminar detenido | Que una persona revise antes de que arranque el colector. |

> **Sobre `--force`:** existe porque a veces hay que restaurar sobre una
> instancia existente. No es la operación normal. Si la usas, primero saca un
> respaldo de lo que estás por pisar.

## 7. Orden de restauración y por qué

**El metastore va primero.** Sin él, la instancia no tiene cuentas ni
tableros; la telemetría sin configuración no le sirve a nadie.

```bash
pg_restore  →  usuarios y tableros existen
volumen CH  →  la telemetría vuelve
```

## 8. Límites y qué hacer ante un fallo parcial

| Situación | Qué hacer |
|---|---|
| El respaldo falló en la fase 3 (ClickHouse) | No hay `.COMPLETO`. Descártalo. El metastore sí quedó, pero el directorio no se restaura. Saca uno nuevo. |
| `pg_restore` falló | **La base quedó como estaba**: `pg_restore` corre dentro de una transacción por defecto y el script usa `--exit-on-error`. Investiga el error antes de reintentar. |
| Los SHA-256 no verifican | El respaldo está **corrupto**. No es recuperable. Restaura desde otro. |
| Se restauró pero la telemetría no aparece | Revisa la retención: al arrancar, ClickHouse puede aplicar el TTL y borrar datos que ya superó la política vigente. Ver la nota de abajo. |

### La nota sobre TTL que sorprende

Al restaurar telemetría vieja en una instancia con una retención **más corta**
que la antigüedad de esos datos, ClickHouse puede eliminarla al arrancar. En
 otras palabras: puedes restaurar correctamente y perder los datos igual.

Si necesitas recuperar telemetría histórica:

1. Levanta la instancia con la retención **más larga** que la historia de los
   datos (Settings → Workspace → Retention Controls).
2. Verifica que la telemetría aparece.
3. Baja la retención de vuelta a lo normal.

Esto es una razón más para respaldar el metastore con calma: la telemetría es
más frágil de lo que parece.

## 9. Verificar que el respaldo sirve

Un respaldo que nunca se restauró es una hipótesis.

- [ ] Al menos una restauración completa probada, en un entorno descartable.
- [ ] `sha256sum -c manifest.sha256` pasa.
- [ ] Los tableros y las alertas aparecen después de restaurar.
- [ ] Hay respaldo **probado** antes de cada actualización de versión.

En `07-PRUEBAS-DE-ACEPTACION.md` está anotado que los scripts **no se ejecutaron
contra Docker** en este entorno: su sintaxis se validó, pero el ciclo completo
respaldo→restauración está pendiente de probar en un servidor.