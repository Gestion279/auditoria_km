# Auditoría de km

Aplicación web para auditar los kilómetros de la flota comparando, por vehículo y mes, las tres fuentes que ya están en Supabase:

| Fuente | Tabla | Qué aporta |
|---|---|---|
| Gestión Vehicular | `gv_indicadores_mensuales` | Km recorridos cargados en la planilla mensual |
| GPS | `gps_reportes` | Distancia informada por el equipo GPS |
| Odómetro YPF | `ypf_consumos` | Diferencia de odómetro entre cargas de combustible |

Es HTML y JavaScript puro, sin build, igual que `indicadores_gv` y `gps_resumen_litrosypf`. Solo **lee** datos: no modifica ninguna tabla.

## Qué hace

- **Vehículo y mes**: tabla con los km de las tres fuentes, la diferencia de Gestión contra la referencia, un estado y el motivo. Se ordena por gravedad.
- **Matriz por vehículo**: patentes × meses coloreadas según el resultado, con los vehículos más problemáticos arriba.
- **Desvíos por tipo**: los casos agrupados por tipo de problema.
- **Detalle de vehículo** (clic en cualquier fila o celda): gráfico de las tres fuentes mes a mes y todas las cargas de YPF con su odómetro, marcando cuáles se usaron y cuáles se descartaron.
- **Registros con más de 15.000 km**: aviso arriba de todo con el total de registros que superan ese máximo en cada base. En Gestión y GPS se cuentan los meses con más de 15.000 km; en YPF, las cargas cuyo odómetro salta más de 15.000 km respecto de la carga anterior del mismo vehículo. Cada base tiene su detalle desplegable con la tabla donde corregir el dato. Esos registros no se modifican en Supabase: se muestran con su valor original y no se usan en los totales ni como referencia. El máximo se cambia en la constante `MAX_KM_REGISTRO` de `index.html`.
- **Exportar CSV** con lo filtrado, listo para abrir en Excel (separador `;` y coma decimal).
- **Uso en celular**: en pantallas chicas la tabla se convierte en tarjetas, los filtros se pliegan detrás del botón "Filtros" y el detalle de vehículo ocupa toda la pantalla.
- **Instalable como app** en Android, iPhone y computadora, con ícono propio y ventana sin barra del navegador.
- **Sin conexión**: si no hay internet, muestra los últimos datos descargados en ese dispositivo y avisa la fecha.

## Instalar en el celular

La app tiene que estar publicada en una dirección `https` (Vercel o GitHub Pages lo hacen solos).

- **Android (Chrome)**: abrí el link y tocá **Instalar app** en el encabezado, o el menú ⋮ → *Instalar aplicación*.
- **iPhone o iPad (Safari)**: tocá **Instalar app** para ver los pasos, o directamente Compartir → *Agregar a inicio*.
- **Computadora (Chrome o Edge)**: botón **Instalar app** o el ícono de instalar en la barra de direcciones.

Cuando publiques cambios importantes, subí el número de `VERSION` en `sw.js` para que los dispositivos que ya la instalaron descarguen la versión nueva.

### Referencia y estados

El **km de referencia** de cada mes es el del GPS. Se reemplaza por el odómetro de YPF cuando el GPS informa 0 horas de motor (equipo sin señal de encendido) o está marcado atípico, siempre que el odómetro cubra al menos el 90 % del mes.

| Estado | Significado |
|---|---|
| Más de 15.000 km | Gestión o GPS informan más de 15.000 km en el mes. Error de carga; no se usa en totales. |
| Imposible | Los km de Gestión darían más de 30 km por litro. Suele ser el odómetro cargado como km. |
| Litros sin km | Gestión tiene litros pero menos de 50 km. |
| Falta en Gestión | El GPS u odómetro registran recorrido y Gestión no. |
| Desvío Gestión | Gestión difiere de la referencia más que la tolerancia, o registra km con el vehículo parado. |
| Desvío GPS / YPF | El GPS y el odómetro no coinciden: posible falla del equipo. |
| GPS sin encendido | El GPS informa 0 horas de motor. |
| GPS atípico | El reporte GPS fue marcado atípico al importarlo. |
| Sin referencia | Hay km en Gestión pero nada contra qué verificarlos. |
| Coincide | Diferencia dentro de la tolerancia. |

La tolerancia (15 % por defecto) se ajusta en pantalla.

Al abrir, el período queda seleccionado en los meses en que están disponibles las tres fuentes. Un mes cuenta para una fuente si tiene datos de al menos la mitad de los vehículos que esa fuente informa en un mes típico, así no se toman meses con datos sueltos ni el mes en curso todavía incompleto. El rango se puede cambiar desde los filtros.

### Limpieza del odómetro de YPF

Las vistas descartan lecturas de relleno (1234, 12345, 123123…), odómetros congelados que se repiten durante semanas, retrocesos y saltos de más de 1.500 km por día. Cada tramo entre dos cargas válidas se reparte entre los meses según los días. Los tramos de más de 62 días no se usan. Por cómo caen las cargas, el km mensual del odómetro tiene un margen de ±10 %.

## Puesta en marcha

### 1. Crear las vistas en Supabase

1. Entrá al proyecto (`https://oixzkvkybqexvrzwzwis.supabase.co`) → **SQL Editor** → *New query*.
2. Pegá el contenido de `supabase/conciliacion_km.sql` y ejecutalo.
3. Se crean tres vistas: `v_ypf_odometro_limpio`, `v_km_ypf_mensual` y `v_km_conciliacion`. Las tablas no se tocan. El script se puede volver a correr.

Las vistas usan `security_invoker`, así que respetan las políticas RLS de las tablas de origen: la app ve exactamente lo que la anon key ya puede leer en esas tablas.

### 2. Conexión

La URL del proyecto y la anon public key están fijas al comienzo del script de `index.html` (`SUPABASE_URL` y `SUPABASE_ANON_KEY`). Todos los usuarios entran directo, sin configurar nada. Si algún día cambia la key, se edita ahí. Nunca uses la `service_role`.

### 3. Publicar

```bash
git init
git add .
git commit -m "Auditoría de km"
git branch -M main
git remote add origin https://github.com/Gestion279/auditoria_km.git
git push -u origin main
```

Después importá el repositorio en Vercel (o activá GitHub Pages). No requiere build: el directorio raíz es el sitio.

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | La aplicación completa, con la conexión al proyecto |
| `manifest.webmanifest` | Nombre, colores e íconos para instalarla como app |
| `sw.js` | Service worker: permite instalarla y abrirla sin conexión |
| `icons/` | Íconos de la app |
| `supabase/conciliacion_km.sql` | Vistas de conciliación |

## Seguridad

Los otros dos repositorios dejan las tablas con políticas que permiten insertar y actualizar con la anon key, y esa key está publicada en el repositorio. Esta app no escribe nada, pero conviene restringir la escritura de `gv_indicadores_mensuales`, `gps_reportes` e `ypf_consumos` a usuarios autenticados.
