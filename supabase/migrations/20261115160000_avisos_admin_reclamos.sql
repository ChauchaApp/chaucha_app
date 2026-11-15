-- Al admin le llegan los reclamos: uno nuevo y cada respuesta del usuario.
-- La identidad ya no pasa por él (se verifica sola), así que su bandeja es
-- de reclamos. La app abre el detalle del reclamo al tocar el aviso
-- (tipo 'reclamo', referencia = id del reclamo).

create or replace function public.fn_aviso_admin_reclamo()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into notificaciones (usuario_id, tipo, referencia_id, contenido)
  select u.id, 'reclamo', new.id,
         format('Nuevo reclamo REC-%s: %s.', lpad(new.numero::text, 4, '0'),
                case new.categoria
                  when 'falla_trabajo' then 'el trabajo falló'
                  when 'no_se_presento' then 'el técnico no se presentó'
                  when 'trato' then 'mal trato'
                  when 'cobro_indebido' then 'cobro indebido'
                  else 'otro problema' end)
    from usuarios u
   where u.rol = 'admin' and u.dado_de_baja_en is null;
  return new;
end $$;

drop trigger if exists trg_aviso_admin_reclamo on public.reclamos;
create trigger trg_aviso_admin_reclamo
  after insert on public.reclamos
  for each row execute function public.fn_aviso_admin_reclamo();

-- Respuesta del usuario: avisa al asesor asignado (o a todos si nadie lo
-- tomó). Los mensajes del sistema (sin autor) y del asesor no avisan.
create or replace function public.fn_aviso_admin_respuesta()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare r reclamos;
begin
  if new.autor_id is null or coalesce(new.es_asesor, false) then
    return new;
  end if;
  select * into r from reclamos where id = new.reclamo_id;
  insert into notificaciones (usuario_id, tipo, referencia_id, contenido)
  select u.id, 'reclamo', r.id,
         format('Respondieron en el reclamo REC-%s.', lpad(r.numero::text, 4, '0'))
    from usuarios u
   where u.rol = 'admin' and u.dado_de_baja_en is null
     and (r.asesor_id is null or u.id = r.asesor_id);
  return new;
end $$;

drop trigger if exists trg_aviso_admin_respuesta on public.reclamo_mensajes;
create trigger trg_aviso_admin_respuesta
  after insert on public.reclamo_mensajes
  for each row execute function public.fn_aviso_admin_respuesta();
