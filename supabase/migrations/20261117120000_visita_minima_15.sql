-- El precio de la visita no puede ser menor a $15.
-- Aplica en tres lugares: el precio por oficio del técnico (tecnico_oficios),
-- el precio base de cada oferta nueva (cotizaciones.precio_base) y el precio
-- acordado en el ticket (cotizaciones.mano_obra).
-- No se usa un CHECK en las tablas: también se evaluaría al actualizar ofertas
-- viejas por debajo de $15 (por ejemplo, al aceptarlas) y las rompería.

-- 1. Los precios configurados por debajo de $15 suben a $15.
update public.tecnico_oficios
   set tarifa_visita = 15
 where tarifa_visita > 0 and tarifa_visita < 15;

update public.perfiles_tecnicos
   set tarifa_base = 15
 where tarifa_base > 0 and tarifa_base < 15;

-- 2. Precio por oficio del técnico. Null o 0 significa "sin configurar".
create or replace function public.fn_visita_minima_oficio()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if new.tarifa_visita > 0 and new.tarifa_visita < 15 then
    raise exception 'El precio mínimo de la visita es $15.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists trg_visita_minima_oficio on public.tecnico_oficios;
create trigger trg_visita_minima_oficio
  before insert or update of tarifa_visita on public.tecnico_oficios
  for each row execute function public.fn_visita_minima_oficio();

-- 3. Ofertas nuevas y tickets. Corre después de trg_cotizacion_validar
--    (los BEFORE se ejecutan por orden alfabético), que ya fijó precio_base.
create or replace function public.fn_visita_minima_cotizacion()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' and new.precio_base < 15 then
    raise exception 'El precio mínimo de la visita es $15. Actualízalo en Mi perfil antes de ofertar.'
      using errcode = 'P0001';
  end if;
  if new.mano_obra is not null and new.mano_obra < 15
     and (tg_op = 'INSERT' or new.mano_obra is distinct from old.mano_obra) then
    raise exception 'El precio mínimo de la visita es $15.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists trg_cotizacion_visita_minima on public.cotizaciones;
create trigger trg_cotizacion_visita_minima
  before insert or update of mano_obra on public.cotizaciones
  for each row execute function public.fn_visita_minima_cotizacion();
