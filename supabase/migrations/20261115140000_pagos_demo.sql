-- Pasarela de pago simulada para los planes (demostración, no cobra).
--
-- La app valida la tarjeta (Luhn, vencimiento y CVV) y al servidor solo
-- llegan la marca y los últimos 4 dígitos: nunca el número completo ni el
-- CVV. El "banco" simulado aprueba todo menos las tarjetas terminadas en
-- 0002, que se rechazan por fondos insuficientes (como en Stripe).
--
-- Los planes pagados se activan solo con un pago aprobado; `suscribirse`
-- queda para volver a Gratis.

create sequence if not exists public.pagos_numero_seq;

create table if not exists public.pagos (
  id uuid primary key default gen_random_uuid(),
  referencia text not null unique,
  tecnico_id uuid not null references public.perfiles_tecnicos(usuario_id) on delete cascade,
  plan_codigo text not null references public.planes(codigo),
  monto numeric(10, 2) not null check (monto >= 0),
  marca text not null check (marca in ('visa', 'mastercard', 'amex', 'diners')),
  ultimos4 text not null check (ultimos4 ~ '^[0-9]{4}$'),
  estado text not null check (estado in ('aprobado', 'rechazado')),
  motivo text,
  suscripcion_id uuid references public.suscripciones(id) on delete set null,
  creado_en timestamptz not null default now()
);

create index if not exists pagos_tecnico on public.pagos (tecnico_id, creado_en desc);

alter table public.pagos enable row level security;
drop policy if exists pagos_lectura on public.pagos;
create policy pagos_lectura on public.pagos
  for select to authenticated
  using (tecnico_id = (select auth.uid()) or public.mi_rol() = 'admin');

create or replace function public.pagar_plan(p_plan text, p_marca text, p_ultimos4 text)
returns public.pagos
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
        v_plan planes;
        v_pago pagos;
        v_sus uuid;
        v_aprobado boolean;
begin
  if public.mi_rol() is distinct from 'tecnico' then
    raise exception 'Solo los técnicos pueden contratar un plan.';
  end if;
  select * into v_plan from planes where codigo = p_plan;
  if not found or v_plan.precio_mensual <= 0 then
    raise exception 'Ese plan no requiere pago.';
  end if;
  if p_marca is null or p_marca not in ('visa', 'mastercard', 'amex', 'diners') then
    raise exception 'No aceptamos esa tarjeta.';
  end if;
  if p_ultimos4 is null or p_ultimos4 !~ '^[0-9]{4}$' then
    raise exception 'Los datos de la tarjeta no son válidos.';
  end if;

  v_aprobado := p_ultimos4 <> '0002';
  if v_aprobado then
    update suscripciones set estado = 'cancelada'
     where tecnico_id = v_uid and estado = 'activa';
    insert into suscripciones (tecnico_id, plan_codigo, fin, origen)
    values (v_uid, p_plan, now() + interval '30 days', 'pago')
    returning id into v_sus;
    perform public.pausar_oficios_sobrantes(v_uid);
  end if;

  insert into pagos (referencia, tecnico_id, plan_codigo, monto, marca, ultimos4, estado, motivo, suscripcion_id)
  values ('PAY-' || lpad(nextval('pagos_numero_seq')::text, 6, '0'), v_uid, p_plan,
          v_plan.precio_mensual, p_marca, p_ultimos4,
          case when v_aprobado then 'aprobado' else 'rechazado' end,
          case when v_aprobado then null else 'El banco rechazó la tarjeta por fondos insuficientes.' end,
          v_sus)
  returning * into v_pago;
  return v_pago;
end $$;

revoke all on function public.pagar_plan(text, text, text) from public, anon;
grant execute on function public.pagar_plan(text, text, text) to authenticated;

-- Los planes pagados ya no se activan sin pago: suscribirse solo vuelve a Gratis.
create or replace function public.suscribirse(p_plan text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if public.mi_rol() is distinct from 'tecnico' then
    raise exception 'Solo los técnicos pueden cambiar de plan.';
  end if;
  if p_plan <> 'gratis' then
    raise exception 'Para activar un plan pagado completa el pago.';
  end if;
  update suscripciones set estado = 'cancelada'
   where tecnico_id = v_uid and estado = 'activa';
  perform public.pausar_oficios_sobrantes(v_uid);
end $$;
