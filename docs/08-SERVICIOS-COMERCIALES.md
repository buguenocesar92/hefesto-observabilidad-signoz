# 08 — Servicios comerciales

A quién le sirve este kit, qué se puede vender, qué límites tiene y **qué no se
puede prometer**.

---

## Qué hueco cubre en el catálogo de Hefesto

Hefesto ya ofrece:

| Producto | Qué hace | Qué NO hace |
|---|---|---|
| **Uptime Kuma** | ¿La página responde sí o no? | No ve el servidor. No ve por qué. No guarda historia de por qué. |
| **Umami** | ¿Cuánta gente entró y de dónde? | Métricas web. Nada de servidor, nada de aplicación. |

**Lo que falta es todo el medio.** SigNoz aporta:

- **Métricas del servidor y de la aplicación** (CPU, memoria, latencia, throughput).
- **Trazas distribuidas**: qué pasó, en qué orden y dónde se fue el tiempo.
- **APM**: qué consulta SQL, qué llamada externa, cuánto tardó cada una.
- **Logs correlacionados** con las trazas.
- **Alertas y tableros** en la misma herramienta.

### Por qué un cliente paga por esto

Porque pasa esto: el cliente llama y dice *"la app está lenta"*. Con Uptime Kuma
sabes que responde. Con Umami sabes que hubo visitas. **Con SigNoz sabes que
el 30 % de las peticiones tarda más de 2 segundos porque una consulta a la
tabla `facturas` no tiene índice.**

Esa es la venta. No es "un dashboard bonito": es pasar de adivinar a medir.

---

## A quién le sirve

| Cliente | Le sirve |
|---|---|
| Pyme con aplicación web propia (Laravel, Node, Django) | **Sí.** Es el caso ideal. |
| Pyme con e-commerce o sistema interno | **Sí**, si hay llamadas lentas que investigar. |
| Empresa con microservicios | **Sí**, pero necesita dimensionamiento mayor al que este kit cubre. |
| Sitio sin código (WordPress, Shopify) | **Parcialmente.** Hay que instrumentar plugins o usar un collector aparte. |
| Cliente que solo quiere uptime | **No.** Uptime Kuma, y es más barato. |

---

## Qué se puede vender

| Servicio | Qué incluye |
|---|---|
| **Despliegue** | Instalar, configurar HTTPS, dejar la UI andando. |
| **Instrumentación** | Meter OpenTelemetry en la app del cliente (Laravel, Node, etc.). |
| **Paneles a medida** | Los que el cliente pida: ventas, operación, performance. |
| **Alertas** | Configurar las alertas y el canal de aviso. |
| **Mantenimiento** | Actualizaciones, respaldos, ajustes de retención. |
| **Diagnóstico** | "La app está lenta": revisar trazas y decir qué pasa. **Este es el servicio de mayor valor.** |

---

## Límites de la edición Community — lo que hay que decir

Verificado en la documentación oficial: la edición Community self-hosted **no
cobra por usuario ni por número de hosts**.

**No verificado:** si impone límites concretos al número de reglas de alerta,
paneles o volumen de telemetría. Antes de comprometer "N alertas" o "M paneles"
en una propuesta, confírmalo en la versión instalada. Está en
`07-PRUEBAS-DE-ACEPTACION.md`.

---

## Lo que NO se puede prometer

Esta sección es la más importante del documento. Si algo de acá se vende y no
se cumple, Hefesto pierde a un cliente.

### 1. "Tiene alertas de disponibilidad" — no

SigNoz **no reemplaza a Uptime Kuma**. No vigila tu sitio desde fuera. No te
avisa si el servidor no responde. Para eso está Uptime Kuma, que es más barato
y más simple.

SigNoz te avisa de cosas que Uptime Kuma no ve: la tasa de error subió, el p95
se disparó, la consulta a la base está tardando.

### 2. "Es multi-tenant / aísla los datos de cada cliente" — no

**SigNoz no es multi-tenant.** Una instancia es para un cliente.

Si Hefesto opera una instancia compartida:

- Los datos de todos viven en **el mismo ClickHouse**.
- El **administrador raíz de la instancia ve todo**.
- El aislamiento depende de que los roles se configuren bien. Un error de
  configuración expone datos de un cliente a otro.
- **No hay separación física.** No es un esquema por cliente ni una base por
  cliente.

Si operas con varios clientes en una instancia, tienes que **escribir en el
contrato qué puede ver cada cliente**. Y entender que esa garantía depende de
que nadie toque los roles.

**Recomendación: una instancia por cliente.** Cuesta más RAM, pero es la única
forma de aislamiento real.

### 3. "Las claves de ingesta protegen el OTLP" — no

**SigNoz self-hosted no usa claves de ingesta.** Verificado en la doc oficial:
tú controlas tu propio pipeline, y para autenticación hay que poner un proxy
inverso delante.

Traducción práctica: **cualquiera que alcance el puerto 4317 o 4318 puede
escribir telemetría en la instancia**. Y si logras que la app se trague un
volumen alto de basura, estás denial-of-service del disco del cliente.

Este kit deja ambos puertos atados a `127.0.0.1`. **No los abras a internet
"porque la app está en otro servidor".** Usa VPN, o proxy con autenticación.
Secuencia recomendada:

1. WireGuard entre los servidores (lo más simple y seguro).
2. Proxy inverso con mTLS exponiendo solo 4318 por HTTPS.
3. Túnel SSH.

### 4. "El tamaño en disco es X" — no lo sé

No hay cifra oficial de "cuánto disco por cliente" para el despliegue de un
nodo. Depende de la cantidad de requests, de si mandas logs, de la retención.

**No inventes el número.** Instala, mide una semana con datos reales y después
cotiza. Si necesitas un número para la propuesta, da un rango amplio y di
explícitamente que es una estimación a confirmar.

Lo que sí puedes afirmar con fundamento: **el consumo crece con la telemetría y
no se autolimita.** Hay que vigilarlo.

### 5. "Es gratis de por vida" — no del todo

La edición Community no cobra por usuario ni por host. Pero:

- Hefesto cobra por la **operación**: despliegue, instrumentación, mantenimiento.
- El **equipo** cobra: 4 GB de RAM, 4 vCPU, disco que crece.
- Las alertas y paneles vía Telegram/Slack requieren configurar el canal.

Cobra por el **servicio**, no por el software. Esa es la propuesta honesta.

### 6. "Guarda los logs para siempre" — no

Retención por defecto: **15 días** logs y trazas, **30 días** métricas.
Verificado en la doc oficial.

Y dos reglas que hay que decir antes de que el cliente se entere después:

1. Cambiar la retención afecta **solo a los datos nuevos**.
2. Al vencer el TTL los datos se **borran de forma definitiva**. Subir la
   retención después no recupera lo perdido.

Si el cliente necesita logs de un año para una auditoría, **eso no es este
producto**. Se necesita un sistema de logs con retención larga (Loki, Elastic,
ClickHouse dedicado).

### 7. "Los tableros y alertas se pueden compartir con el cliente" — con cuidado

Los tableros se pueden compartir por enlace o con la UI completa. **Antes de
compartir, confirma en la configuración de compartir si expone datos del
servidor** (métricas de infraestructura, nombres de host, IPs internas).

No verifiqué en detalle el comportamiento de los enlaces públicos en la
versión instalada. Confírmalo antes de poner un panel con métricas de
infraestructura en un enlace abierto.

### 8. Supabase — no

El contrato de Hefesto pide evaluar Supabase. Resultado:

- **No lo ofrezcas como parte de este kit.**
- Supabase solo podría cubrir el metastore, y **no se verificó** versión de
  Postgres, extensiones, TLS ni comportamiento con el migrador.
- **ClickHouse sigue siendo obligatorio** para la telemetría. Supabase no
  resuelve el problema de disco, que es el que más importa.

Si un cliente insiste, es un proyecto aparte, con pruebas, y probablemente
terminaría siendo "SigNoz normal". Revísalo con calma.

---

## Modelo de precios sugerido

| Plan | Qué incluye | Para qué |
|---|---|---|
| **Instalación** | despliegue + instrumentación de 1 app + 3 paneles + 2 alertas + 1 taller | Pyme que quiere partir |
| **Operado** | lo anterior + mantenimiento mensual + respaldos + guardia de alertas | Pyme que no tiene equipo |
| **Diagnóstico** | sesión de análisis de trazas, con informe | Cliente con un problema concreto |

El margen está en el **diagnóstico** y en el **operado**, no en instalar
software. Uptime Kuma y Umami ya están en el catálogo: quien los tiene
instalados y no quiere contratar, se los instala él solo. A quién le duele el
dinero es a quien **necesita a alguien que entienda sus trazas**.

---

## Qué debe saber Hefesto antes de vender esto

- [ ] Qué versión de Node o PHP tiene el cliente (para la instrumentación).
- [ ] Cuántas apps y qué volumen aproximado de requests.
- [ ] Si manda logs a otro sistema ya (para no duplicar).
- [ ] Cuánto disco tiene y cuánto crece por semana.
- [ ] Quién va a recibir las alertas y a qué hora.
- [ ] Qué pasa si el cliente quiere la instancia en **su** servidor y no en el
      de Hefesto.

Y una pregunta que siempre conviene hacer: **¿qué harían si esta herramienta
se cae mañana?** Si la respuesta es "el negocio se para", el plan Operado es
obligatorio, no opcional.