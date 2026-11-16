-- El cliente puede reportar un problema cuando el técnico marca el trabajo
-- como terminado y aún no lo confirma (botón "Reportar problema" junto a
-- "Confirmar trabajo"). Lo demás de crear_reclamo queda igual.

create or replace function public.crear_reclamo(
  p_solicitud_id uuid, p_categoria text, p_descripcion text, p_evidencias text[] default '{}')
returns reclamos language plpgsql security definer set search_path = public as $$
declare
  yo uuid := auth.uid();
  s solicitudes_servicio;
  c cotizaciones;
  r reclamos;
  codigo text;
  ruta text;
begin
  select * into s from solicitudes_servicio where id = p_solicitud_id;
  select * into c from cotizaciones where solicitud_id = p_solicitud_id and estado = 'aceptada' limit 1;
  if s.id is null or c.id is null then raise exception 'No encontramos ese servicio.'; end if;
  if yo is null or (yo is distinct from s.cliente_id and yo is distinct from c.tecnico_id) then
    raise exception 'Este servicio no es tuyo.';
  end if;
  -- Por confirmar: el técnico dice que terminó y el cliente ve un problema
  -- antes de confirmar. Completada: dentro de los 30 días de garantía.
  if s.estado = 'por_confirmar' then
    if yo is distinct from s.cliente_id then
      raise exception 'Solo el cliente puede reportar antes de confirmar.';
    end if;
  elsif s.estado <> 'completada' or s.completada_en is null then
    raise exception 'Solo puedes reportar servicios terminados.';
  elsif now() > s.completada_en + interval '30 days' then
    raise exception 'La garantía de 30 días de este servicio ya terminó.';
  end if;
  if p_categoria not in ('falla_trabajo','no_se_presento','trato','cobro_indebido','otro') then
    raise exception 'Elige el tipo de problema.';
  end if;
  if p_categoria = 'falla_trabajo' and yo = c.tecnico_id then
    raise exception 'Elige otro tipo de problema.';
  end if;
  if length(trim(coalesce(p_descripcion, ''))) < 20 then
    raise exception 'Cuéntanos qué pasó con al menos 20 caracteres.';
  end if;
  -- Las fotos tienen que estar en la carpeta de quien reporta.
  foreach ruta in array coalesce(p_evidencias, '{}') loop
    if split_part(ruta, '/', 1) <> yo::text then
      raise exception 'Una de las fotos no es válida.';
    end if;
  end loop;

  begin
    insert into reclamos (solicitud_id, cotizacion_id, autor_id, contra_id, categoria, descripcion, evidencias)
    values (s.id, c.id, yo,
      case when yo = s.cliente_id then c.tecnico_id else s.cliente_id end,
      p_categoria, trim(p_descripcion), coalesce(p_evidencias, '{}'))
    returning * into r;
  exception when unique_violation then
    raise exception 'Ya tienes un reclamo abierto para este servicio.';
  end;

  codigo := 'REC-' || lpad(r.numero::text, 4, '0');
  insert into reclamo_mensajes (reclamo_id, texto) values (r.id,
    'Recibimos tu reclamo ' || codigo || '. Un asesor de ChauchaApp lo está evaluando y te escribirá por aquí. También te avisaremos con una notificación.');
  insert into notificaciones (usuario_id, tipo, referencia_id, contenido)
  values (yo, 'reclamo', r.id, 'Tu reclamo ' || codigo || ' lo está evaluando un asesor.');
  return r;
end $$;
