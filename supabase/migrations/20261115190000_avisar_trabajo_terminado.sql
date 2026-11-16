-- Aviso al cliente cuando el técnico marca el trabajo como terminado
-- (por_confirmar). Antes no le llegaba nada y tenía que refrescar para ver
-- que ya podía confirmar. Al confirmar, el técnico ya recibe 'cierre'.

create or replace function public.fn_avisar_trabajo_terminado()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
as $$
declare
  v_tecnico text;
begin
  select u.nombres into v_tecnico
  from cotizaciones c
  join usuarios u on u.id = c.tecnico_id
  where c.solicitud_id = new.id and c.estado = 'aceptada'
  limit 1;

  insert into notificaciones (usuario_id, tipo, referencia_id, contenido)
  values (
    new.cliente_id, 'trabajo_terminado', new.id,
    coalesce(v_tecnico, 'El técnico') || ' terminó el trabajo "'
      || left(new.descripcion, 40) || '". Revisa las fotos y confírmalo.'
  );
  return new;
end $$;

revoke all on function public.fn_avisar_trabajo_terminado() from public, anon, authenticated;

drop trigger if exists trg_avisar_trabajo_terminado on public.solicitudes_servicio;
create trigger trg_avisar_trabajo_terminado
  after update of estado on public.solicitudes_servicio
  for each row
  when (new.estado = 'por_confirmar' and old.estado is distinct from new.estado)
  execute function public.fn_avisar_trabajo_terminado();
