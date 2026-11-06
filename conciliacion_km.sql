-- =====================================================================
-- Conciliación de kilómetros: Gestión Vehicular vs GPS vs Odómetro YPF
-- Proyecto Supabase: oixzkvkybqexvrzwzwis
--
-- Tablas que usa (ya existen, no se modifican):
--   public.ypf_consumos              -> odómetro de cada carga
--   public.gps_reportes              -> distancia_km mensual del GPS
--   public.gv_indicadores_mensuales  -> km mensual de Gestión Vehicular
--
-- Crea:
--   public.v_ypf_odometro_limpio     -> cargas con odómetro válido
--   public.v_km_ypf_mensual          -> km por patente y mes según odómetro
--   public.v_km_conciliacion         -> las tres fuentes lado a lado
--
-- Se puede correr más de una vez: borra y recrea solo estas vistas,
-- nunca las tablas.
-- =====================================================================

drop view if exists public.v_km_conciliacion, public.v_km_ypf_mensual,
                    public.v_ypf_odometro_limpio cascade;

-- ---------------------------------------------------------------------
-- 1) Odómetros limpios
-- ---------------------------------------------------------------------
create or replace view public.v_ypf_odometro_limpio
  with (security_invoker = true) as
with cargas as (
  select
    upper(replace(vehiculo_dominio, ' ', '')) as dominio,
    fecha::timestamp                          as fecha,
    odometro::numeric                         as odo
  from public.ypf_consumos
  where coalesce(es_combustible, true)
    and odometro is not null
    and odometro >= 1000                                  -- descarta 101, 123, 236, 308...
    and odometro not in (1234, 12345, 123456, 123123,     -- valores de relleno
                         1515, 2500, 5000, 10000, 11111, 99999)
),
-- Un mismo odómetro repetido en cargas separadas por más de 3 días
-- es un valor congelado (ej. KBO829 = 322112 durante 5 meses): se descarta.
-- Si se repite dentro de 3 días es una carga partida: se queda la primera.
agrupado as (
  select dominio, odo, min(fecha) as fecha
  from cargas
  group by dominio, odo
  having max(fecha) - min(fecha) <= interval '3 days'
),
-- Pasada 1: una lectura se acepta si es coherente con la anterior
-- o con la siguiente (avance >= 0 y <= 1500 km por día).
p1 as (
  select *,
    lag(odo)   over w as odo_prev, lag(fecha)  over w as f_prev,
    lead(odo)  over w as odo_next, lead(fecha) over w as f_next
  from agrupado
  window w as (partition by dominio order by fecha)
),
v1 as (
  select dominio, fecha, odo from p1
  where (odo_prev is not null and odo >= odo_prev
         and odo - odo_prev <= 1500 * greatest(extract(epoch from fecha - f_prev)/86400, 1))
     or (odo_next is not null and odo_next >= odo
         and odo_next - odo <= 1500 * greatest(extract(epoch from f_next - fecha)/86400, 1))
),
-- Pasada 2: misma regla sobre las lecturas que sobrevivieron.
p2 as (
  select *,
    lag(odo)   over w as odo_prev, lag(fecha)  over w as f_prev,
    lead(odo)  over w as odo_next, lead(fecha) over w as f_next
  from v1
  window w as (partition by dominio order by fecha)
)
select dominio, fecha, odo
from p2
where (odo_prev is not null and odo >= odo_prev
       and odo - odo_prev <= 1500 * greatest(extract(epoch from fecha - f_prev)/86400, 1))
   or (odo_next is not null and odo_next >= odo
       and odo_next - odo <= 1500 * greatest(extract(epoch from f_next - fecha)/86400, 1));

-- ---------------------------------------------------------------------
-- 2) Km mensuales según odómetro YPF
--    Cada tramo entre dos cargas válidas se reparte entre los meses
--    que abarca, en proporción a los días.
-- ---------------------------------------------------------------------
create or replace view public.v_km_ypf_mensual
  with (security_invoker = true) as
with tramos as (
  select dominio,
         fecha                       as f_ini,
         lead(fecha) over w          as f_fin,
         lead(odo)   over w - odo    as km
  from public.v_ypf_odometro_limpio
  window w as (partition by dominio order by fecha)
),
validos as (
  select * from tramos
  where f_fin is not null
    and km >= 0
    and f_fin - f_ini <= interval '62 days'   -- tramos más largos no se usan
),
partes as (
  select v.dominio,
         date_trunc('month', m)::date as mes,
         greatest(v.f_ini, m) as d_ini,
         least(v.f_fin, m + interval '1 month') as d_fin,
         v.km,
         extract(epoch from v.f_fin - v.f_ini) as seg_tramo
  from validos v
  cross join lateral generate_series(date_trunc('month', v.f_ini),
                                     date_trunc('month', v.f_fin),
                                     interval '1 month') as m
)
select dominio,
       to_char(mes, 'YYYY-MM') as periodo,
       round(sum(km * extract(epoch from d_fin - d_ini) / nullif(seg_tramo, 0)))::int as km_ypf,
       -- cobertura: qué parte del mes está cubierta por tramos válidos (0 a 1)
       round(least(sum(extract(epoch from d_fin - d_ini))
             / extract(epoch from (mes + interval '1 month') - mes), 1)::numeric, 2) as cobertura_ypf
from partes
where d_fin > d_ini
group by dominio, mes;

-- ---------------------------------------------------------------------
-- 3) Conciliación de las tres fuentes
-- ---------------------------------------------------------------------
create or replace view public.v_km_conciliacion
  with (security_invoker = true) as
with gv as (
  select upper(replace(dominio, ' ', '')) as dominio,
         substr(mes_orden::text, 1, 4) || '-' || substr(mes_orden::text, 5, 2) as periodo,
         sum(km) as km_gv, sum(litros) as litros_gv,
         max(nullif(zona, '')) as zona, max(nullif(modelo, '')) as modelo
  from public.gv_indicadores_mensuales
  group by 1, 2
),
gps as (
  select upper(replace(vehiculo_dominio, ' ', '')) as dominio, periodo,
         sum(distancia_km) as km_gps,
         sum(litros_ypf)   as litros_gps,
         coalesce(sum(horas_motor), 0) as horas_motor,
         bool_or(es_atipico) as gps_atipico,
         max(nullif(zona_periodo, '')) as zona, max(nullif(modelo_periodo, '')) as modelo
  from public.gps_reportes
  group by 1, 2
),
cargas as (
  select upper(replace(vehiculo_dominio, ' ', '')) as dominio,
         to_char(fecha, 'YYYY-MM') as periodo,
         sum(litros) as litros_ypf, count(*) as cargas_ypf
  from public.ypf_consumos
  where coalesce(es_combustible, true)
  group by 1, 2
),
base as (
  select coalesce(gv.dominio, gps.dominio, y.dominio) as dominio,
         coalesce(gv.periodo, gps.periodo, y.periodo) as periodo,
         round(gv.km_gv)   as km_gv,
         round(gps.km_gps) as km_gps,
         y.km_ypf,
         y.cobertura_ypf,
         gv.litros_gv, gps.litros_gps, gps.horas_motor, gps.gps_atipico,
         c.litros_ypf, c.cargas_ypf,
         coalesce(gv.zona, gps.zona)     as zona,
         coalesce(gv.modelo, gps.modelo) as modelo
  from gv
  full join gps on gps.dominio = gv.dominio and gps.periodo = gv.periodo
  full join public.v_km_ypf_mensual y
         on y.dominio = coalesce(gv.dominio, gps.dominio)
        and y.periodo = coalesce(gv.periodo, gps.periodo)
  left join cargas c
         on c.dominio = coalesce(gv.dominio, gps.dominio, y.dominio)
        and c.periodo = coalesce(gv.periodo, gps.periodo, y.periodo)
)
select b.*,
       -- referencia: GPS, salvo equipo sin señal de encendido (horas_motor = 0)
       -- o atípico, en cuyo caso se usa el odómetro YPF si cubre el mes
       case
         when b.km_gps > 0 and b.horas_motor > 0 and not coalesce(b.gps_atipico, false) then b.km_gps
         when b.cobertura_ypf >= 0.9 then b.km_ypf
         else b.km_gps
       end as km_referencia,
       round(100.0 * (b.km_gv - b.km_gps) / nullif(b.km_gps, 0), 1) as dif_gv_vs_gps_pct,
       case when b.cobertura_ypf >= 0.9
            then round(100.0 * (b.km_gps - b.km_ypf) / nullif(b.km_ypf, 0), 1)
       end as dif_gps_vs_ypf_pct,
       case
         when b.km_gv > 0 and b.litros_gv > 0 and b.km_gv / b.litros_gv > 30
              then 'GV: km imposibles para los litros'
         when coalesce(b.litros_gv, 0) > 0 and coalesce(b.km_gv, 0) = 0
              then 'GV: litros sin km'
         when b.km_gps > 0 and b.horas_motor = 0
              then 'GPS: horas_motor = 0 (posible equipo sin encendido)'
         when b.gps_atipico then 'GPS: marcado atípico'
         when b.km_gps > 0 and abs(b.km_gv - b.km_gps) / b.km_gps > 0.15
              then 'GV difiere del GPS más de 15 %'
         when b.cobertura_ypf >= 0.9 and b.km_ypf > 0
              and abs(b.km_gps - b.km_ypf) / b.km_ypf > 0.15
              then 'GPS difiere del odómetro YPF más de 15 %'
       end as alerta
from base b;

-- Permisos de lectura para la app (anon key) y usuarios logueados.
-- Las vistas usan security_invoker: respetan las políticas RLS de las
-- tablas de origen, así que solo muestran lo que esas tablas ya permiten leer.
grant select on public.v_ypf_odometro_limpio to anon, authenticated;
grant select on public.v_km_ypf_mensual      to anon, authenticated;
grant select on public.v_km_conciliacion     to anon, authenticated;

-- Ejemplos de uso:
--   select * from v_km_conciliacion where alerta is not null order by periodo desc, dominio;
--   select * from v_km_conciliacion where dominio = 'AE817KM' order by periodo;
