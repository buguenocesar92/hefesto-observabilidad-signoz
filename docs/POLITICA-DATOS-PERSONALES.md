# Política de tratamiento de datos personales — Observabilidad (SigNoz) (Hefesto Studio)

Estado: vigente desde 2026-10-20. Responsable del tratamiento: el cliente que
opera el kit. Este documento describe qué datos guarda el kit, por qué, cuánto
tiempo los retiene y cómo se ejercen los derechos del titular (Ley 21.719).

## 1. Qué datos guarda este kit

El kit de observabilidad (SigNoz) guarda, por sistema observado:

- **Trazas**: servicio, nombre de la operación, duración, estado y los
  **atributos** de la traza (cabeceras HTTP, URL, parámetros y cuerpos cuando
  la instrumentación los incluye).
- **Métricas**: series temporales de contadores, histogramas y gauges, con sus
  etiquetas (que pueden contener nombres de host, rutas o identificadores).
- **Logs**: mensajes de la aplicación con su nivel, marca de tiempo y
  atributos, que pueden incluir **IP de origen** y datos del usuario.
- **Identidad del operador**: usuario del panel, correo y hash de contraseña.
- **Copias locales de respaldo**: `backups/<timestamp>/` con el dump de
  PostgreSQL, la tela de ClickHouse y la configuración del kit.

Las cabeceras HTTP y los cuerpos de traza son el punto de riesgo: si la
instrumentación captura `Authorization` o datos de negocio, el kit los almacena
sin saberlo.

## 2. Qué datos NO guarda este kit

- El `.env` **no** se copia en claro al respaldo: solo sus nombres de variable
  (`env.vars`) y, si hay un receptor `age` configurado, el `.env` cifrado
  (`env.age`). Ver `docs/CONTRATO-RESPALDO.md`, regla 5.
- El kit no guarda datos de negocio: solo lo que los sistemas observados envían.

## 3. Base legal y deberes

- **Minimización**: el kit guarda lo que la instrumentación envía. La responsabilidad es del que instrumenta: no enviar cabeceras `Authorization`, cuerpos con datos personales ni cabeceras `Cookie` en atributos de traza. Se recomienda configurar la redacción de atributos sensibles en el colector.
- **Finalidad**: observar el comportamiento de los sistemas del cliente. Los datos no se usan para otros fines ni se ceden a terceros.
- **Seguridad**: los respaldos se cifran en reposo hacia el destino del
  operador, la clave privada no está en este servidor y el `.env` nunca sale
  en claro.
- **Auditoría**: cada respaldo y cada restauración dejan registro en
  `logs/restore.log` con origen, sha256 verificado, destino y resultado. Es
  registro de actividades de tratamiento: no guarda valores de secretos.

## 4. Retención

| Dato | Dónde | Retención por defecto | Quién lo borra |
|---|---|---|---|
| Trazas, métricas y logs | ClickHouse (volúmenes `telemetrystore` y `telemetrykeeper`) | según la retención que configure el operador en SigNoz | el operador |
| Metastore | PostgreSQL (volumen `metastore`) | mientras el kit exista | el operador |
| Cuentas del panel | PostgreSQL (volumen `metastore`) | mientras la cuenta exista | el operador |
| Respaldos en disco | `backups/<timestamp>/` | **a definir por el operador**; el kit no borra nada por su cuenta | el operador |
| Registro de auditoría | `logs/restore.log` | append-only; se trunca por política del cliente | el operador |

**El kit no borra respaldos ni datos por su cuenta.** Borrar es una decisión del
operador, porque un respaldo borrado no se recupera.

## 5. Derechos del titular (acceso, rectificación y supresión)

1. **Acceso**: entregar los datos de un titular concreto desde la interfaz del
   kit o desde el dump de la base.
2. **Rectificación**: corregir los datos desde la interfaz del kit.
3. **Supresión**: eliminar el registro y dejar constancia de la supresión en el
   registro de auditoría.
4. **Revocación del consentimiento**: si el tratamiento depende del
   consentimiento, eliminar el registro.

El kit garantiza que los datos son localizables, corregibles y borrables; el
cliente es quien conoce la identidad de los titulares.

## 6. Verificación

- `bats tests/backup_restore.bats` comprueba, con datos sintéticos, que el
  `.env` no queda en claro, que el manifiesto lleva las cinco claves, que un
  artefacto alterado se rechaza y que un destino no vacío aborta la
  restauración.
- `gitleaks` corre en CI sobre el repositorio y su historial.
