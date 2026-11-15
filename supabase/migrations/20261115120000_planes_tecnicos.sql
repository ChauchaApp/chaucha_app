-- Planes de suscripción para técnicos: Gratis, Pro y Plus.
--
-- Los límites viven en la tabla `planes` (única fuente: la app los lee de
-- ahí). Se validan en el servidor, no solo en la app:
--   * tope de propuestas al mes y rango, en fn_validar_cotizacion;
--   * tope de oficios activos, en un trigger de tecnico_oficios.
-- Los errores llevan en HINT un código estable ("plan:...") que la app
-- reconoce para ofrecer subir de plan.
--
-- Rango efectivo = least(rango elegido, tope del plan) + bono por
-- reputación, con tope global de 50 km: el bono premia el mérito encima
-- del plan.

-- 1. Catálogo de planes.
create table if not exists public.planes (
  codigo text primary key check (codigo in ('gratis', 'pro', 'plus')),
  nombre text not null,
  precio_mensual numeric(10, 2) not null check (precio_mensual >= 0),
  cotizaciones_mes integer check (cotizaciones_mes is null or cotizaciones_mes > 0),
  rango_max_m integer not null check (rango_max_m > 0),
  oficios_max integer not null check (oficios_max > 0),
  prioridad integer not null,
  destacado boolean not null default false,
  orden integer not null
);

comment on column public.planes.cotizaciones_mes is 'Propuestas por mes calendario (hora de Ecuador). Null: ilimitadas.';

insert into public.planes
  (codigo, nombre, precio_mensual, cotizaciones_mes, rango_max_m, oficios_max, prioridad, destacado, orden)
values
  ('gratis', 'Gratis', 0, 15, 5000, 3, 1, false, 1),
  ('pro', 'Pro', 6, null, 15000, 5, 2, false, 2),
  ('plus', 'Plus', 12, null, 30000, 8, 3, true, 3)
on conflict (codigo) do update set
  nombre = excluded.nombre,
  precio_mensual = excluded.precio_mensual,
  cotizaciones_mes = excluded.cotizaciones_mes,
  rango_max_m = excluded.rango_max_m,
  oficios_max = excluded.oficios_max,
  prioridad = excluded.prioridad,
  destacado = excluded.destacado,
  orden = excluded.orden;

alter table public.planes enable row level security;
drop policy if exists planes_lectura on public.planes;
create policy planes_lectura on public.planes
  for select to authenticated using (true);

-- 2. Suscripciones. Solo se escriben con funciones (suscribirse, cron).
create table if not exists public.suscripciones (
  id uuid primary key default gen_random_uuid(),
  tecnico_id uuid not null references public.perfiles_tecnicos(usuario_id) on delete cascade,
  plan_codigo text not null references public.planes(codigo),
  inicio timestamptz not null default now(),
  fin timestamptz not null,
  estado text not null default 'activa' check (estado in ('activa', 'vencida', 'cancelada')),
  origen text not null default 'demo' check (origen in ('demo', 'admin', 'pago')),
  creado_en timestamptz not null default now(),
  check (fin > inicio)
);

create unique index if not exists suscripciones_una_activa
  on public.suscripciones (tecnico_id) where estado = 'activa';

alter table public.suscripciones enable row level security;
drop policy if exists suscripciones_lectura on public.suscripciones;
create policy suscripciones_lectura on public.suscripciones
  for select to authenticated
  using (tecnico_id = (select auth.uid()) or public.mi_rol() = 'admin');

-- Plan vigente de un técnico (sin suscripción activa: Gratis).
create or replace function public.plan_de(p_tecnico uuid)
returns public.planes
language sql
stable
security definer
set search_path to 'public'
as $$
  select pl.* from planes pl
  where pl.codigo = coalesce(
    (select s.plan_codigo from suscripciones s
      where s.tecnico_id = p_tecnico and s.estado = 'activa' and s.fin > now()
      order by s.fin desc limit 1),
    'gratis');
$$;

-- Campos calculados para leerlos junto al perfil (PostgREST).
create or replace function public.plan_codigo(p public.perfiles_tecnicos)
returns text language sql stable security definer set search_path to 'public'
as $$ select (public.plan_de(p.usuario_id)).codigo $$;

create or replace function public.plan_rango_max_m(p public.perfiles_tecnicos)
returns integer language sql stable security definer set search_path to 'public'
as $$ select (public.plan_de(p.usuario_id)).rango_max_m $$;

create or replace function public.plan_oficios_max(p public.perfiles_tecnicos)
returns integer language sql stable security definer set search_path to 'public'
as $$ select (public.plan_de(p.usuario_id)).oficios_max $$;

-- Inicio del mes calendario en hora de Ecuador.
create or replace function public.inicio_mes_ecuador()
returns timestamptz language sql stable
as $$ select date_trunc('month', now() at time zone 'America/Guayaquil') at time zone 'America/Guayaquil' $$;

-- 3. Oficios activos o pausados (al bajar de plan, los que sobran).
alter table public.tecnico_oficios
  add column if not exists activo boolean not null default true;

create or replace function public.fn_limite_oficios()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_plan planes;
begin
  if not new.activo or (tg_op = 'UPDATE' and old.activo) then
    return new;
  end if;
  v_plan := public.plan_de(new.tecnico_id);
  if (select count(*) from tecnico_oficios t
       where t.tecnico_id = new.tecnico_id and t.activo
         and t.oficio_id <> new.oficio_id) >= v_plan.oficios_max then
    raise exception 'Tu plan % permite hasta % oficios activos.', v_plan.nombre, v_plan.oficios_max
      using hint = 'plan:limite_oficios';
  end if;
  return new;
end $$;

drop trigger if exists trg_limite_oficios on public.tecnico_oficios;
create trigger trg_limite_oficios
  before insert or update of activo on public.tecnico_oficios
  for each row execute function public.fn_limite_oficios();

-- Pausa los oficios que sobran según el plan vigente (se quedan los de
-- menor id). No borra nada: el técnico decide cuáles reactivar.
create or replace function public.pausar_oficios_sobrantes(p_tecnico uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_max integer := (public.plan_de(p_tecnico)).oficios_max;
        v_pausados integer;
begin
  update tecnico_oficios t set activo = false
   where t.tecnico_id = p_tecnico
     and t.activo
     and t.oficio_id not in (
       select x.oficio_id from tecnico_oficios x
        where x.tecnico_id = p_tecnico and x.activo
        order by x.oficio_id limit v_max);
  get diagnostics v_pausados = row_count;
  return v_pausados;
end $$;

revoke all on function public.pausar_oficios_sobrantes(uuid) from public, anon, authenticated;

-- Todos arrancan en Gratis: se aplica su tope de oficios.
select public.pausar_oficios_sobrantes(p.usuario_id) from public.perfiles_tecnicos p;

-- 4. Suscribirse (modo demo: 30 días, sin cobro). 'gratis' cancela el plan.
create or replace function public.suscribirse(p_plan text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if public.mi_rol() is distinct from 'tecnico' then
    raise exception 'Solo los técnicos pueden suscribirse a un plan.';
  end if;
  if not exists (select 1 from planes where codigo = p_plan) then
    raise exception 'Ese plan no existe.';
  end if;

  update suscripciones set estado = 'cancelada'
   where tecnico_id = v_uid and estado = 'activa';

  if p_plan <> 'gratis' then
    insert into suscripciones (tecnico_id, plan_codigo, fin, origen)
    values (v_uid, p_plan, now() + interval '30 days', 'demo');
  end if;

  perform public.pausar_oficios_sobrantes(v_uid);
end $$;

revoke all on function public.suscribirse(text) from public, anon;
grant execute on function public.suscribirse(text) to authenticated;

-- Mi plan, cuándo vence y cuántas propuestas llevo este mes.
create or replace function public.mi_plan()
returns table(codigo text, fin timestamptz, cotizaciones_usadas integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select (public.plan_de(auth.uid())).codigo,
         (select s.fin from suscripciones s
           where s.tecnico_id = auth.uid() and s.estado = 'activa' and s.fin > now()
           order by s.fin desc limit 1),
         (select count(*)::int from cotizaciones c
           where c.tecnico_id = auth.uid() and c.creado_en >= public.inicio_mes_ecuador());
$$;

revoke all on function public.mi_plan() from public, anon;
grant execute on function public.mi_plan() to authenticated;

-- 5. Vencimiento diario: vuelve a Gratis, pausa oficios y avisa.
create or replace function public.vencer_suscripciones()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare r record; v_total integer := 0;
begin
  for r in
    update suscripciones s set estado = 'vencida'
     where s.estado = 'activa' and s.fin <= now()
    returning s.tecnico_id, s.plan_codigo
  loop
    perform public.pausar_oficios_sobrantes(r.tecnico_id);
    insert into notificaciones (usuario_id, tipo, contenido)
    values (r.tecnico_id, 'plan',
            'Tu plan ' || initcap(r.plan_codigo) || ' venció. Volviste al plan Gratis.');
    v_total := v_total + 1;
  end loop;
  return v_total;
end $$;

revoke all on function public.vencer_suscripciones() from public, anon, authenticated;

select cron.unschedule('vencer-suscripciones')
 where exists (select 1 from cron.job where jobname = 'vencer-suscripciones');
select cron.schedule('vencer-suscripciones', '15 5 * * *', 'select public.vencer_suscripciones()');

-- 6. La propuesta respeta el plan: tope al mes, oficio activo y rango.
create or replace function public.fn_validar_cotizacion()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_oficio integer;
        v_plan planes;
begin
  if (select suspendido_hasta from usuarios where id = new.tecnico_id) > now() then
    raise exception 'Tu cuenta está suspendida y no puedes enviar propuestas por ahora';
  end if;
  select oficio_id into v_oficio from solicitudes_servicio where id = new.solicitud_id;
  if (select estado from solicitudes_servicio where id = new.solicitud_id) not in ('abierta', 'cotizada') then
    raise exception 'La solicitud ya no recibe propuestas';
  end if;

  v_plan := public.plan_de(new.tecnico_id);
  if v_plan.cotizaciones_mes is not null
     and (select count(*) from cotizaciones c
           where c.tecnico_id = new.tecnico_id
             and c.creado_en >= public.inicio_mes_ecuador()) >= v_plan.cotizaciones_mes then
    raise exception 'Ya enviaste las % propuestas de este mes del plan %.', v_plan.cotizaciones_mes, v_plan.nombre
      using hint = 'plan:limite_cotizaciones';
  end if;

  if not exists (select 1 from tecnico_oficios t
                  where t.tecnico_id = new.tecnico_id and t.oficio_id = v_oficio and t.activo) then
    raise exception 'Este oficio está pausado en tu plan. Actívalo en Mi perfil para ofertar.'
      using hint = 'plan:oficio_pausado';
  end if;

  if exists (select 1 from solicitudes_servicio s, perfiles_tecnicos p
              where s.id = new.solicitud_id and p.usuario_id = new.tecnico_id
                and s.ubicacion is not null and p.ubicacion_actual is not null
                and not st_dwithin(s.ubicacion, p.ubicacion_actual,
                      least(least(p.rango_cobertura_m, v_plan.rango_max_m) + p.rango_bonus_m, 50000))) then
    raise exception 'Esta solicitud está fuera del rango de tu plan %.', v_plan.nombre
      using hint = 'plan:fuera_de_rango';
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

-- 7. Lo que ve el técnico: solo oficios activos y rango con el tope del plan.
drop policy if exists solicitudes_lectura on public.solicitudes_servicio;
create policy solicitudes_lectura on public.solicitudes_servicio
  for select to authenticated
  using (
    cliente_id = (select auth.uid())
    or public.mi_rol() = 'admin'
    or public.es_tecnico_cotizante(id)
    or (public.mi_rol() = 'tecnico'
        and public.es_tecnico_verificado()
        and estado = any (array['abierta', 'cotizada'])
        and exists (select 1 from tecnico_oficios t
                     where t.tecnico_id = (select auth.uid())
                       and t.oficio_id = solicitudes_servicio.oficio_id
                       and t.activo))
  );

create or replace function public.solicitudes_cercanas(p_tecnico uuid)
returns table(solicitud_id uuid, descripcion text, metros integer, creado_en timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select s.id, s.descripcion, round(st_distance(s.ubicacion, p.ubicacion_actual))::int, s.creado_en
  from perfiles_tecnicos p
  cross join lateral public.plan_de(p.usuario_id) pl
  join tecnico_oficios t on t.tecnico_id = p.usuario_id and t.activo
  join solicitudes_servicio s on s.oficio_id = t.oficio_id
  where p.usuario_id = p_tecnico
    and s.estado = 'abierta'
    and st_dwithin(s.ubicacion, p.ubicacion_actual,
          least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000))
  order by 3;
$$;

create or replace function public.solicitudes_en_mapa()
returns table(solicitud_id uuid, descripcion text, oficio_id integer, metros integer,
              lat double precision, lng double precision, creado_en timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $$
  select s.id, s.descripcion, s.oficio_id,
         round(st_distance(s.ubicacion, p.ubicacion_actual))::int,
         st_y(s.ubicacion::geometry), st_x(s.ubicacion::geometry), s.creado_en
  from perfiles_tecnicos p
  cross join lateral public.plan_de(p.usuario_id) pl
  join tecnico_oficios t on t.tecnico_id = p.usuario_id and t.activo
  join solicitudes_servicio s on s.oficio_id = t.oficio_id
  where p.usuario_id = auth.uid()
    and p.verificado
    and s.estado = 'abierta'
    and st_dwithin(s.ubicacion, p.ubicacion_actual,
          least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000))
  order by 4;
$$;

-- 8. Lo que ve el cliente: primero el plan, después el nivel, la
-- calificación y la distancia. "destacado" marca a quien sale primero por
-- pagar, para mostrarlo con transparencia.
create or replace function public.tecnicos_elegibles(p_solicitud uuid)
returns table(tecnico_id uuid, nombre text, nivel text, prioridad integer,
              calificacion numeric, metros integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select p.usuario_id, trim(u.nombres || ' ' || u.apellidos), n.nombre, n.prioridad, p.calificacion_promedio,
         round(st_distance(s.ubicacion, p.ubicacion_actual))::int
  from solicitudes_servicio s
  join tecnico_oficios t on t.oficio_id = s.oficio_id and t.activo
  join perfiles_tecnicos p on p.usuario_id = t.tecnico_id
  cross join lateral public.plan_de(p.usuario_id) pl
  join usuarios u on u.id = p.usuario_id
  join niveles_gamificacion n on n.id = p.nivel_id
  where s.id = p_solicitud
    and st_dwithin(s.ubicacion, p.ubicacion_actual,
          least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000))
  order by pl.prioridad desc, n.prioridad desc, p.calificacion_promedio desc, 6;
$$;

drop function if exists public.tecnicos_cercanos(double precision, double precision, integer, integer, integer);

create function public.tecnicos_cercanos(
  p_lat double precision,
  p_lng double precision,
  p_oficio_id integer default null,
  p_radio_m integer default 10000,
  p_limite integer default 20
)
returns table(
  tecnico_id uuid, nombres text, apellidos text, foto_perfil_ruta text,
  oficios text[], calificacion numeric, total_resenas integer, metros integer,
  lat double precision, lng double precision, tarifa_base numeric, nivel text,
  plan text, destacado boolean
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
               where t.tecnico_id = p.usuario_id and t.activo order by o.nombre),
         p.calificacion_promedio, p.total_resenas,
         round(st_distance(p.ubicacion_actual, c.g))::int,
         st_y(st_snaptogrid(p.ubicacion_actual::geometry, 0.005)),
         st_x(st_snaptogrid(p.ubicacion_actual::geometry, 0.005)),
         case
           when p_oficio_id is not null then public.tarifa_visita(p.usuario_id, p_oficio_id)
           else coalesce(
             (select min(nullif(t.tarifa_visita, 0)) from tecnico_oficios t
               where t.tecnico_id = p.usuario_id and t.activo),
             p.tarifa_base)
         end,
         n.nombre,
         pl.codigo,
         pl.destacado
  from perfiles_tecnicos p
  join usuarios u on u.id = p.usuario_id
  join niveles_gamificacion n on n.id = p.nivel_id
  cross join lateral public.plan_de(p.usuario_id) pl
  cross join centro c
  where p.verificado
    and p.ubicacion_actual is not null
    and st_dwithin(p.ubicacion_actual, c.g, p_radio_m)
    and exists (select 1 from tecnico_oficios t
                 where t.tecnico_id = p.usuario_id and t.activo
                   and (p_oficio_id is null or t.oficio_id = p_oficio_id))
  order by pl.prioridad desc, n.prioridad desc, p.calificacion_promedio desc, 8
  limit p_limite;
$$;

revoke all on function public.tecnicos_cercanos(double precision, double precision, integer, integer, integer) from public, anon;
grant execute on function public.tecnicos_cercanos(double precision, double precision, integer, integer, integer) to authenticated;
