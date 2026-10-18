# 09 — Exportación y traspaso

Cómo se sacan los datos de SigNoz, qué formatos son reales y qué se puede o no
se puede traspasar a otra plataforma.

> **Distinción importante, y va en serio:** en este kit **no hay ningún
> conector implementado hacia ningún sistema externo**. No hay sincronización
> con Odoo, ni con el ERP del cliente, ni con nada. Todo lo de acá es una guía
> de integración y exportación manual. Un CSV exportado **no** es una
> sincronización automática.

---

## Qué es realmente portable

| Dato | ¿Se puede sacar? | Dificultad |
|---|---|---|
| **Trazas, métricas, logs** | Sí, vía API o consulta SQL a ClickHouse | Media. Voluminosa y dependiente del esquema interno. |
| **Tableros** | Sí, la UI tiene export | Baja. |
| **Reglas de alerta** | Sí, export desde la UI | Baja. |
| **Usuarios y organizaciones** | A mano, vía el metastore | Baja, pero es una base de datos viva: no la edites a la ligera. |

### Exportar tableros

En la UI: abrir el tablero → **Export**. Sale un archivo que se puede volver a
importar en otra instancia.

Es el camino más limpio para migrar una instancia a otro servidor sin perder los
paneles. El formato puede cambiar entre versiones: prueba a importar antes de
confiar.

### Exportar alertas

Mismo patrón: la UI permite exportar la definición de una regla. Vuelve a crear
la alerta en la instancia destino y prueba que dispara.

### Exportar telemetría

Acá está lo difícil. La telemetría vive en ClickHouse, con el esquema interno de
SigNoz. Dos caminos:

1. **API de consulta de SigNoz** (la que usa la UI). Exporta lo que elijó un
   dashboard.
2. **Consultar ClickHouse directamente** con `clickhouse-client`. Da acceso a
   todo, pero **te ata al esquema interno**, que cambia entre versiones.

```bash
# Ejemplo de forma, no de consulta verificada:
# el esquema exacto de las tablas debe confirmarse en la instancia
docker compose exec -T signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT ... FORMAT JSONEachRow"
```

> **No dejé una consulta SQL exacta en este documento.** El nombre y la forma
> de las tablas internas de SigNoz no son un contrato estable. Poner una consulta
> sin verificar sería inventar la API, y justo en un documento que
> dice "no inventes".

**Para traspasar telemetría entre dos instancias SigNoz, lo razonable es el
respaldo de volúmenes que hace `scripts/backup-signoz.sh`**, no un export. Para
llevar datos a **otra herramienta**, ahí sí hay que exportar con criterio: lo que
el cliente realmente necesita mirar (los últimos 7 días, un servicio, un tipo de
error), no todo.

---

## Traspaso a Odoo u otra plataforma

**No hay conector.** Y probablemente no debería haberlo todavía. Esto es lo que
se puede hacer:

### Lo que sí funciona: informe manual y periódico

1. En SigNoz, exportar lo relevante (un CSV o JSON del panel).
2. Llevarlo al sistema destino (a mano o con una importación masiva del ERP).
3. Repetir cada semana o cada mes.

Es tedioso y no se automatiza. **Dilo así desde el principio.** Un cliente que
cree que hay sincronización automática y se entere al mes siguiente es un
cliente enojado.

### Lo que haría falta para automatizar

Un servicio propio (un cron en Python o Node que):

1. Consulta la API de SigNoz según un horario.
2. Mapea los campos al modelo de Odoo.
3. Escribe por la API de Odoo.

Hefesto no lo construyó. Si un cliente lo necesita, es un **proyecto aparte**,
con su propio presupuesto, porque:

- Requiere mantenerlo contra las versiones de ambas plataformas.
- Hay que decidir qué datos van: ¿una métrica de latencia tiene un equivalente
  razonable en un ERP? Generalmente no.
- Sin una API pública estable de SigNoz documentada para este uso, hay que
  verificar cada llamada contra la versión instalada.

### Un mal ejemplo que hay que evitar

"Integrar las métricas de SigNoz en el dashboard de Odoo para que el gerente
las vea junto a las ventas."

Tiene tres problemas:

1. No hay conector.
2. Las métricas de observabilidad y las ventas no se mezclan bien: una escala es
   "peticiones por segundo" y la otra "pesos venta del mes".
3. Si el gerente solo mira el panel de Odoo, va a ignorar los p95 y las alertas
   de error. **El dashboard equivocado es peor que no tener dashboard.**

Mejor: que el gerente mire el panel de SigNoz cuando haya un problema, y que
reciba alertas por Slack cuando algo se rompe.

---

## Traspaso de una instancia a otro servidor (migración Hefesto)

Este sí es un caso real y cubierto.

### Escenario: cliente se va o cambia de VPS

1. **Respaldo** en el servidor viejo:
   ```bash
   sudo ./scripts/backup-signoz.sh --destino /var/backups/signoz \
        --etiqueta mudanza-de-servidor
   ```
2. **Copia** la carpeta del respaldo al servidor nuevo.
3. **Instala** el kit en el nuevo (misma versión).
4. **Restaura**:
   ```bash
   sudo ./scripts/restore-signoz.sh --respaldo /ruta/al/respaldo
   ```
5. **Verifica**: tableros, alertas, y que lleguen datos nuevos.
6. **Apaga** la instancia vieja.

### Escenario: cambio de versión

Ver `06-ACTUALIZACIONES-Y-REVERSION.md`.

---

## Lo que hay que decirle al cliente

| Petición | Respuesta honesta |
|---|---|
| "Bájenme los datos en Excel" | Sí, export desde la UI. Manual. |
| "Conecten esto con Odoo" | No hay conector. Es un proyecto aparte. |
| "Quiero las alertas en Slack" | Sí, se configura en la UI. |
| "Quiero los logs de un año" | Este producto no. Retención configurable, pero el volumen no da. |
| "Muébanme todo a otro servidor" | Sí, con respaldo y restauración. |
| "Quiero los datos en otra herramienta" | Sí, por API, pero hay que definir qué datos y a qué frecuencia. |

**La trampa que hay que evitar:** decir "se puede integrar" cuando lo que
existe es una API que alguien puede usar. Hay API; no hay integración. La
diferencia es el trabajo.