-- Aviso a los técnicos cuando se publica una solicitud que pueden tomar.
-- Antes solo se enteraban si tenían el inicio abierto; ahora les llega una
-- notificación (campanita y push por trg_notificacion_push) al instante.
-- Mismo filtro que solicitudes_cercanas: técnico verificado, con el oficio
-- activo y la solicitud dentro de su rango (con el tope de su plan).

create or replace function public.fn_avisar_solicitud_nueva()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
as $$
begin
  if new.estado <> 'abierta' or new.ubicacion is null then
    return new;
  end if;

  insert into notificaciones (usuario_id, tipo, referencia_id, contenido)
  select p.usuario_id, 'solicitud_nueva', new.id,
         o.nombre || ' a ' ||
           case when c.metros < 1000 then c.metros || ' m'
                else replace(round(c.metros / 1000.0, 1)::text, '.', ',') || ' km'
           end
           || ': "' || left(new.descripcion, 60) || '"'
  from perfiles_tecnicos p
  join usuarios u on u.id = p.usuario_id
  join tecnico_oficios t on t.tecnico_id = p.usuario_id
                        and t.oficio_id = new.oficio_id
                        and t.activo
  join oficios o on o.id = new.oficio_id
  cross join lateral public.plan_de(p.usuario_id) pl
  cross join lateral (
    select round(st_distance(new.ubicacion, p.ubicacion_actual))::int as metros
  ) c
  where p.verificado
    and p.ubicacion_actual is not null
    and p.usuario_id <> new.cliente_id
    and u.dado_de_baja_en is null
    and (u.suspendido_hasta is null or u.suspendido_hasta <= now())
    and st_dwithin(new.ubicacion, p.ubicacion_actual,
          least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000));

  return new;
end $$;

revoke all on function public.fn_avisar_solicitud_nueva() from public, anon, authenticated;

drop trigger if exists trg_avisar_solicitud_nueva on public.solicitudes_servicio;
create trigger trg_avisar_solicitud_nueva
  after insert on public.solicitudes_servicio
  for each row
  execute function public.fn_avisar_solicitud_nueva();
