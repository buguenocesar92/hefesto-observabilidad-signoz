# Ejemplos — DEMOSTRACIÓN, NO ES CÓDIGO PRODUCTIVO

Todo lo que está en esta carpeta es **demostración**. Sirve para que el cliente
vea cómo se ve la telemetría funcionando, y para que Hefesto tenga una base
real al cotizar. Antes de ponerlo en producción hay que revisarlo, ajustarlo al
proyecto real y probarlo.

## Qué hay aquí

| Archivo | Qué demuestra |
|---|---|
| `node/` | App Node.js + Express instrumentada con OpenTelemetry. Trazas, métricas y logs salen hacia SigNoz. |
| `laravel/` | Receta equivalente para Laravel (muy común en Pymes chilenas). |
| `dashboards/panel-base-latencia.md` | Cómo armar el panel de latencia p95 y tasa de error. |
| `alertas/regla-alerta-demo.md` | Regla de alerta de ejemplo y cómo probarla. |

## Antes de copiar y pegar

1. **Nada de esto se ejecutó.** No hay Docker ni servidor en el entorno donde
   se construyó el kit. Ver `docs/07-PRUEBAS-DE-ACEPTACION.md`.
2. **Verifica las versiones de los paquetes** antes de fijar un `package.json` en
   un proyecto real. Las versiones de esta carpeta se consultaron en npm y
   Packagist el 2026-10-16 y pueden estar viejas para cuando leas esto.
3. **El punto OTLP de ejemplo apunta a `127.0.0.1:4317`.** Si la app corre en
   otra máquina, cambia el host. Y recuerda: si cambias el bind de OTLP en el
   `compose.yaml` para que acepte conexiones remotas, estás abriendo un puerto
   sin autenticación. Lee `docs/08-SERVICIOS-COMERCIALES.md` antes.
4. **El exportador usa `http://` sin TLS**, porque así viene el compose por
   defecto. En producción, si el tráfico sale del servidor, usa VPN o TLS.
5. **Sin secretos.** No hay contraseñas, tokens ni API keys en estos archivos, y
   no debe haberlos nunca.

## Dónde mirar los resultados

Una vez levantada la instancia y enviando telemetría:

- **Traces** → busca el servicio en la barra superior. Verás cada request con su
  duración y sus spans hijos.
- **Metrics** → la app expone latencia y tasa de error.
- **Logs** → lo que escribas con `console.log` aparece aquí.

Eso es justamente lo que Uptime Kuma y Umami, que ya están en el catálogo de
Hefesto, **no** hacen: Uptime Kuma te dice si la página responde; Umami te dice
cuánta gente entró. Ninguno de los dos te muestra por qué una consulta tardó
2,4 segundos. Eso es lo que aporta SigNoz.