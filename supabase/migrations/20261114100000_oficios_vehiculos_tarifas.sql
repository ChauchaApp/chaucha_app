-- Oficios de vehículos (los mecánicos entran como técnicos) y precio de la
-- visita por oficio: quien hace plomería y mecánica no cobra lo mismo.

-- 1. Categoría de oficio y los de vehículos.
alter table public.oficios
  add column if not exists categoria text not null default 'hogar'
    check (categoria in ('hogar', 'vehiculos'));

insert into public.oficios (nombre, categoria) values
  ('Mecánica automotriz', 'vehiculos'),
  ('Mecánica de motos', 'vehiculos'),
  ('Electricidad automotriz', 'vehiculos'),
  ('Llantería y vulcanizadora', 'vehiculos')
on conflict (nombre) do nothing;

-- 2. Precio de la visita por oficio. Arranca con la tarifa única que tenía
-- cada técnico; tarifa_base queda como respaldo.
alter table public.tecnico_oficios
  add column if not exists tarifa_visita numeric(10, 2)
    check (tarifa_visita is null or tarifa_visita >= 0);

update public.tecnico_oficios t
   set tarifa_visita = p.tarifa_base
  from public.perfiles_tecnicos p
 where p.usuario_id = t.tecnico_id
   and t.tarifa_visita is null
   and p.tarifa_base > 0;

drop policy if exists tec_oficios_update on public.tecnico_oficios;
create policy tec_oficios_update on public.tecnico_oficios
  for update to authenticated
  using (tecnico_id = (select auth.uid()))
  with check (tecnico_id = (select auth.uid()));

-- Precio de la visita de un técnico para un oficio.
create or replace function public.tarifa_visita(p_tecnico uuid, p_oficio integer)
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select nullif(t.tarifa_visita, 0) from tecnico_oficios t
      where t.tecnico_id = p_tecnico and t.oficio_id = p_oficio),
    (select nullif(p.tarifa_base, 0) from perfiles_tecnicos p
      where p.usuario_id = p_tecnico)
  );
$$;

-- 3. La oferta toma el precio del oficio de la solicitud.
create or replace function public.fn_validar_cotizacion()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_oficio integer;
begin
  if (select suspendido_hasta from usuarios where id = new.tecnico_id) > now() then
    raise exception 'Tu cuenta está suspendida y no puedes enviar propuestas por ahora';
  end if;
  select oficio_id into v_oficio from solicitudes_servicio where id = new.solicitud_id;
  if (select estado from solicitudes_servicio where id = new.solicitud_id) not in ('abierta', 'cotizada') then
    raise exception 'La solicitud ya no recibe propuestas';
  end if;
  new.precio_base := public.tarifa_visita(new.tecnico_id, v_oficio);
  if new.precio_base is null or new.precio_base <= 0 then
    raise exception 'Configura el precio de la visita de este oficio en Mi perfil antes de ofertar.';
  end if;
  new.mano_obra := null;
  new.materiales := 0;
  new.estado := 'pendiente';
  return new;
end $$;

-- 4. "Cerca de ti": el precio del oficio buscado o, sin filtro, el menor.
create or replace function public.tecnicos_cercanos(
  p_lat double precision,
  p_lng double precision,
  p_oficio_id integer default null,
  p_radio_m integer default 10000,
  p_limite integer default 20
)
returns table(
  tecnico_id uuid, nombres text, apellidos text, foto_perfil_ruta text,
  oficios text[], calificacion numeric, total_resenas integer, metros integer,
  lat double precision, lng double precision, tarifa_base numeric, nivel text
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with centro as (select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g)
  select p.usuario_id, u.nombres, u.apellidos, u.foto_perfil_ruta,
         array(select o.nombre from tecnico_oficios t
               join oficios o on o.id = t.oficio_id
               where t.tecnico_id = p.usuario_id order by o.nombre),
         p.calificacion_promedio, p.total_resenas,
         round(st_distance(p.ubicacion_actual, c.g))::int,
         st_y(st_snaptogrid(p.ubicacion_actual::geometry, 0.005)),
         st_x(st_snaptogrid(p.ubicacion_actual::geometry, 0.005)),
         case
           when p_oficio_id is not null then public.tarifa_visita(p.usuario_id, p_oficio_id)
           else coalesce(
             (select min(nullif(t.tarifa_visita, 0)) from tecnico_oficios t
               where t.tecnico_id = p.usuario_id),
             p.tarifa_base)
         end,
         n.nombre
  from perfiles_tecnicos p
  join usuarios u on u.id = p.usuario_id
  join niveles_gamificacion n on n.id = p.nivel_id
  cross join centro c
  where p.verificado
    and p.ubicacion_actual is not null
    and st_dwithin(p.ubicacion_actual, c.g, p_radio_m)
    and (p_oficio_id is null or exists (
          select 1 from tecnico_oficios t
          where t.tecnico_id = p.usuario_id and t.oficio_id = p_oficio_id))
  order by n.prioridad desc, p.calificacion_promedio desc, 8
  limit p_limite;
$$;

-- 5. Datos opcionales del vehículo en la solicitud:
-- {"tipo": "auto", "marca": "...", "modelo": "...", "anio": 2015}.
alter table public.solicitudes_servicio
  add column if not exists vehiculo jsonb;
