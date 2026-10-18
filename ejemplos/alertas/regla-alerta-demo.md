# Regla de alerta de ejemplo (DEMOSTRACIÓN)

Guion para crear una alerta real en SigNoz. Sirve para la demo y como base de
los alertedores que se ofrecen como servicio.

## Qué conviene alertar en una Pyme

No todo. Una alerta que suena y no pasa nada entrena al cliente a ignorar todo
lo demás. Empieza con **pocas y confiables**.

| # | Alerta | Por qué |
|---|---|---|
| 1 | Tasa de error > 5 % durante 5 min | El cliente está perdiendo ventas. Esta es la importante. |
| 2 | p95 de latencia > 2 s durante 10 min | Se le está cayendo la sesión. |
| 3 | La instancia está caída | Uptime Kuma ya cubre esto. **No dupliques**: déjala en Uptime Kuma y enlaza ambas alertas. |
| 4 | Disco por encima de 80 % | La telemetría crece sin parar; el servidor se queda sin espacio y se cae todo. |

## Alerta de ejemplo: tasa de error

### Definición

- **Nombre**: `API - errores por encima de 5%`
- **Tipo**: alerta de métrica (ratio de errores).
- **Condición**: ratio de peticiones con status >= 500 sobre el total de
  peticiones del servicio, **superior a 0,05**.
- **Duración mínima**: 5 minutos continuos (evita que un reinicio de 40
  segundos dispare la alerta).
- **Grado de severidad**: crítica.

### Por qué "durante 5 minutos"

Porque una alerta por un evento aislado es ruido. Un despliegue que reinicia el
proceso produce 30 segundos de errores y vuelve a la normalidad. Con la ventana
de 5 minutos, eso no despierta a nadie a las 3 de la mañana.

### Canales

Configura el aviso a un canal que el cliente mire de verdad:

- Correo (viene incluido).
- Slack, Teams o Telegram vía webhook.
- **No** lo mandes solo a un correo que nadie abre.

Si usas Slack, el webhook es una credencial: va en el gestor de secretos de
Coolify o en el `.env`, nunca en un documento ni en git.

### Cómo se crea (pasos en la UI)

1. **Alerts** → **New Alert Rule**.
2. Elegir el tipo de alerta que corresponda a la medida (métrica).
3. Elegir la fuente de datos: el servicio instrumentado.
4. Armar la condición con el editor visual.
5. Fijar la ventana de duración.
6. Seleccionar laOrg y los servicios a los que aplica.
7. Configurar el canal de notificación.
8. **Save**.

> **Pendiente de verificar:** no transcribo la consulta ni el payload JSON de
> la alerta. El formato de la API de alertas de SigNoz cambia entre versiones.
> Créala en la UI y expórtala si necesitas versionarla.

## Probar la alerta sin esperar una caída real

Con la app de demostración de `ejemplos/node/`:

```bash
# Tasa de error al 100 % — dispara la alerta 1
DEMO_RATE_ERROR=1.0 node --require ./otel.js server.js

# Latencia alta y sostenida — dispara la alerta 2
DEMO_LATENCIA_MS=3000 node --require ./otel.js server.js
```

Después de disparar:

- **Deja la alerta quieta un rato.** La ventana de 5 minutos es a propósito: si
  la dejas pasar, no dispara, y alguien va a pensar que está mala.
- Confirma que **llega** la notificación al canal configurado.
- Deja de generar errores y confirma que la alerta se resuelve sola.

Una alerta que no se puede probar es una alerta que no funciona.

## Límites de la edición Community

Lo verificado en la documentación oficial: la edición Community self-hosted no
cobra por usuario ni por número de hosts, y la configuración de alertas y
paneles es parte del producto.

**No verifiqué** si la edición Community impone límites concretos al número de
reglas de alerta o de paneles. Antes de vender "N alertas" en una propuesta,
confírmalo en la versión que vas a instalar. Queda anotado en
`docs/07-PRUEBAS-DE-ACEPTACION.md`.