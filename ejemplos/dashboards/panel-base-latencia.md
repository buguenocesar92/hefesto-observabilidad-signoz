# Panel de ejemplo: latencia y errores (DEMOSTRACIÓN)

Guion para armar un panel en la UI de SigNoz. Sirve para la demo con el
cliente y como punto de partida para los paneles reales.

**No hay un JSON de exportación acá a propósito.** El formato de export de
paneles de SigNoz es interno y cambia entre versiones; un archivo hecho a mano
sería o inválido o engañoso. Armalo en la UI y expórtalo desde ahí cuando
servir.

## Por qué este panel y no otro

Es el panel que responde la pregunta que el cliente siempre hace: **"¿está
lento o se cae?"**

- Uptime Kuma ya le dice si la página responde sí o no.
- Umami le dice cuánta gente entró.
- **Este panel** le dice qué tan rápido responde y con qué tasa de error, y —
  lo importante — dónde se va el tiempo dentro de cada petición.

## Qué armar

### Panel 1 — Latencia p95 por servicio

- Tipo: serie temporal.
- Fuente: señales del servicio (métricas).
- Medida: **p95** (percentil 95) de la duración de las peticiones HTTP del
  servicio.
- Agrupar por: `service.name`.
- Ventana: últimas 1 y 6 horas.

Por qué p95 y no el promedio: el promedio esconde la experiencia de quien
sufrió. Si el 90 % responde en 80 ms y el 10 % en 4 s, el promedio dice 460 ms y
nadie está experiencing 4 s. El p95 sí lo muestra.

### Panel 2 — Tasa de error

- Tipo: serie temporal.
- Medida: **ratio** de peticiones con `http.status_code >= 500` sobre el total de
  peticiones, del mismo servicio.
- Unidad: porcentaje.

Un gráfico con dos ejes (p95 arriba, tasa de error abajo) ayuda a separar
problemas: si sube la latencia y no suben los errores, casi siempre es
rendimiento. Si suben los dos, es un error, no lentitud.

### Panel 3 — Las 5 operaciones más lentas

- Tipo: tabla o serie temporal.
- Agrupar por: nombre de la operación o del span, tomando la duración máxima.
- Ordenar descendente, top 5.

Este es el que más valor entrega en una primera reunión con el cliente: en
general no es "la aplicación está lenta", es **una consulta concreta** dentro de
la aplicación.

## Cómo se crea (pasos en la UI)

1. Abrir SigNoz y entrar a **Dashboards**.
2. **New Dashboard** → poner nombre, por ejemplo `API - Salud general`.
3. **Add widget** → elegir el tipo de panel.
4. En el constructor, elegir la fuente de datos (el servicio instrumentado).
5. Armar la medida con el editor visual de la UI. La UI va proponiendo los
   campos disponibles según el servicio; los nombres exactos dependen de cómo se
  instrumentó la app.
6. Guardar el panel y **Export** cuando quieras respaldo.

> **Pendiente de verificar:** no transcribo acá la consulta en el lenguaje de
> SigNoz. Puedo confirmar la existencia del editor y de los tipos de panel,
> pero la sintaxis exacta de las consultas debe verla quien la arme en la UI
> con la versión instalada. Prefiero dejarlo escrito así antes que poner una
> consulta inventada que después no funcione en la demo.

## Una nota sobre el volumen de la demo

Para que el panel se vea bien en una reunión, hay que tener **pocos servicios y
pocos datos**. Un panel con 40 servicios y 15 días de historia no se entiende en
pantalla compartida. Demo con un servicio, tres paneles, seis horas de datos.