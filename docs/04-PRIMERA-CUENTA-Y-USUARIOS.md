# 04 — Primera cuenta y usuarios

Procedimiento para crear el primer administrador sin dejar una ventana abierta,
cerrar el registro de cuentas nuevas y entender el modelo de permisos.

> Fuente principal: <https://signoz.io/docs/manage/administrator-guide/configuration/root-user/>

---

## El problema que estamos resolviendo

En un despliegue típico, después de `docker compose up` la instancia queda
abierta en el puerto 8080 y **cualquiera que llegue puede registrarse como el
primer usuario y quedarse como administrador de los datos del cliente**.

Es una ventana de segundos o minutos, pero es real. En un VPS con la UI
expuesta, a veces alguien la encuentra con un escáner.

Este kit la cierra creando el administrador **en el arranque**, antes de que
exista la primera sesión web.

---

## Procedimiento: primer administrador

### 1. Configura las variables **antes** del primer arranque

En el `.env` (o en las variables de Coolify):

```dotenv
SIGNOZ_USER_ROOT_ENABLED=true
SIGNOZ_USER_ROOT_EMAIL=admin@tucliente.cl
SIGNOZ_USER_ROOT_PASSWORD=<contraseña fuerte>
SIGNOZ_USER_ROOT_ORG_NAME=<nombre del cliente>
```

Disponibile desde **SigNoz v0.112.0**. Este kit usa v0.146.0.

> **Importante:** si `SIGNOZ_USER_ROOT_PASSWORD` tiene una clave el espacio
> o símbolos raros, escápalos en el `.env` o usa una contraseña alfanumérica
> larga. Una contraseña que rompa el parseo del archivo deja la instancia sin
> administrador y sin avisar.

### 2. Levanta

```bash
docker compose up -d
```

El root user se crea durante el arranque de `signoz-signoz-0`.

### 3. Entra

En `https://observabilidad.tucliente.cl` (o `http://<ip>:8080`):

- Correo: el de `SIGNOZ_USER_ROOT_EMAIL`
- Contraseña: la de `SIGNOZ_USER_ROOT_PASSWORD`

Confirma que tienes acceso a **Settings → Org Settings**.

### 4. Borra las variables del `.env` y reinicia

Esto es importante y se salta todo el mundo:

```bash
# Deja vacío o elimina estas tres líneas del .env:
# SIGNOZ_USER_ROOT_ENABLED=
# SIGNOZ_USER_ROOT_EMAIL=
# SIGNOZ_USER_ROOT_PASSWORD=
docker compose up -d
```

Tres razones:

1. La contraseña queda escrita en texto plano en el servidor.
2. El root user no se puede cambiar desde la UI, así que la única forma de
   rotarla es volver a poner la variable.
3. Si alguien lee el `.env`, tiene la cuenta administradora del cliente.

`SIGNOZ_USER_ROOT_ORG_NAME` puede quedarse: no es un secreto.

### 5. Restringe quién entra a la UI

El registro de cuentas nuevas se gestiona en la UI, desde
**Settings → Members / Organization**. Revisa:

- ¿Hay algún usuario o invitación pendiente de tu primera prueba? Bórralos.
- ¿Quiénes pueden invitar usuarios?

**Pendiente de verificar:** no confirmé el nombre exacto de cada pantalla ni si
la edición Community permite **deshabilitar globalmente** las invitaciones, en
lugar de_invitar uno por uno. Lo que sí es cierto y verifiqué: la creación de
cuentas en la UI requiere Authentication (correo) enabled, y el self-hosted usa
un modelo de usuarios con roles dentro de una organización. Antes de ofrecer
"cerrar el registro" como servicio, confirma los controles exactos en la versión
que instales. Queda anotado en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## Instancia existente (ya desplegada sin root user)

Si ya tienes la instancia andando y quieres crear el administrador por
variables, hay un paso extra que la doc marca explícitamente:

**El nombre de la organización en la base debe coincidir** con
`SIGNOZ_USER_ROOT_ORG_NAME`. Si no, el root user se crea pero no se asocia a la
organización correcta y no puedes entrar.

En el metastore PostgreSQL:

```sql
UPDATE organizations SET name = '<org-name>';
```

Luego pones las variables, reinicias y verificas.

> No ejecutes ese `UPDATE` a ciegas. Lee primero el valor actual
> (`SELECT id, name FROM organizations;`) para saber a qué lo estás cambiando.

---

## Modelo de permisos

Lo verificado:

- SigNoz organiza usuarios en **organizaciones** (orgs).
- Cada usuario tiene **roles** dentro de la organización.
- Existe un modelo de **service accounts** para integraciones automáticas.

**No verifiqué en detalle la matriz exacta de roles** (qué puede y qué no puede
hacer un "member" frente a un "admin" en la versión v0.146.0). Si vas a
vender un servicio con varios usuarios por cliente, revisa la página de roles en
la versión instalada antes de prometer nada. Queda en
`07-PRUEBAS-DE-ACEPTACION.md`.

Principio práctico que sí aplica: **el usuario root no puede borrarse, editarse
ni cambiarse la contraseña desde la UI**. Es a propósito: evita quedarse sin
administradores. Pero también significa que la única rotación de esa
contraseña pasa por las variables de entorno y un reinicio.

---

## Multi-tenant: lo que NO hay

**SigNoz no es multi-tenant por defecto.** Una instancia es para un cliente.

No existe aislamiento entre organizaciones dentro de una instancia. Si dos
clientes comparten instancia:

- Los usuarios de la organización A **no deberían** ver los datos de la B si el
  modelo de roles se mantiene estricto.
- Pero los datos **viven en el mismo ClickHouse**. No hay separación física.
- El administrador raíz de la instancia ve todo.
- Cualquier error de configuración de roles expone datos de un cliente a otro.

**Si Hefesto opera una instancia compartida, documenta en el contrato qué puede
ver cada cliente.** Si no estás dispuesto a sostener esa garantía, instala una
instancia por cliente. Es más caro en RAM, pero es la única forma de aislamiento
real.

Detalle en `08-SERVICIOS-COMERCIALES.md`.

---

## Lista de verificación de seguridad

Antes de entregar la instancia al cliente:

- [ ] `SIGNOZ_USER_ROOT_PASSWORD` borrada del `.env`.
- [ ] `.env` con permisos `600`.
- [ ] UI accesible por HTTPS, no por HTTP plano.
- [ ] `SIGNOZ_BIND_ADDRESS` en `127.0.0.1` si hay proxy.
- [ ] OTLP (4317/4318) **no** expuesto a internet.
- [ ] ClickHouse (9000/8123), Keeper (9181) y Postgres (5432) **no** publicados.
- [ ] No quedan usuarios de prueba ni invitaciones pendientes.
- [ ] Hay un respaldo del metastore probado. Ver `05-RESPALDOS-Y-RESTAURACION.md`.