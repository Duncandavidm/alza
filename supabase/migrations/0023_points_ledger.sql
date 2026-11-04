-- Ledger unico de puntos: usado por "Facturas que suman" (fuente
-- 'factura', cuando se construya el verificador DGI real) y por los dos
-- modulos nuevos de esta pasada: tarjeta en comercios aliados ('tarjeta')
-- y ahorro/habitos ('ahorro'/'habito'). 'ajuste' es para correcciones
-- manuales (nunca se edita una fila existente, se inserta una nueva).
--
-- Principio de diseño: NINGUNA fuente escribe aqui directo desde el
-- cliente (ni siquiera 'factura', que hoy no tiene verificador todavia).
-- Todo pasa por `award_points()`, SECURITY DEFINER, solo invocable por
-- la service role key desde una Edge Function — igual que
-- check_and_increment_rate_limit en 0013_rate_limiting.sql.

create table public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste')),
  -- Identificador unico de ESTE movimiento dentro de su fuente (ej. el
  -- id de dgi_receipts, el id de transaccion del proveedor de tarjeta,
  -- "habito:racha:2026-11-04:user123"). El UNIQUE de abajo es la unica
  -- garantia real de "nada suma dos veces".
  external_ref text not null,
  points integer not null,
  status text not null check (status in ('pendiente', 'confirmado', 'anulado')),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  -- Sin updated_at/trigger a proposito: las filas de este ledger NUNCA
  -- se editan. Una correccion es una fila nueva con otro external_ref
  -- (ej. "<ref>:reversal") y puntos negativos.
  unique (source, external_ref)
);

create index points_ledger_user_id_idx on public.points_ledger (user_id);
create index points_ledger_user_status_idx on public.points_ledger (user_id, status);

alter table public.points_ledger enable row level security;

create policy "points_ledger_select_own" on public.points_ledger
  for select
  using ((select auth.uid()) = user_id);

-- Sin policies de insert/update/delete para authenticated/anon: solo
-- award_points() (SECURITY DEFINER, ejecutable unicamente por la
-- service role) puede escribir aqui.

-- Saldo agregado por usuario, confirmado vs pendiente. security_invoker
-- para que respete el RLS de points_ledger de quien consulte (cada
-- usuario solo ve su propio saldo, nunca el de otro).
create view public.points_balances
  with (security_invoker = true)
  as
  select
    user_id,
    coalesce(sum(points) filter (where status = 'confirmado'), 0) as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente'), 0) as pending_points
  from public.points_ledger
  group by user_id;

-- Reglas y topes configurables por fuente — nunca hardcodeadas en una
-- Edge Function ni en la app. Se ajustan desde el Table Editor.
create table public.points_rules (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste')),
  key text not null,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  unique (source, key)
);

alter table public.points_rules enable row level security;
-- Sin policies: nadie de anon/authenticated la lee directo (las reglas
-- las aplica el servidor al calcular puntos, el cliente no necesita
-- verlas para nada todavia).

create trigger points_rules_set_updated_at
  before update on public.points_rules
  for each row execute procedure public.set_updated_at();

insert into public.points_rules (source, key, value) values
  ('factura', 'points_per_dollar', '1'::jsonb),
  ('habito', 'monthly_cap_points', '200'::jsonb),
  ('ahorro', 'points_per_goal_met', '500'::jsonb),
  ('tarjeta', 'daily_cap_points_per_user', '300'::jsonb);

-- `award_points`: unico punto de escritura del ledger. Idempotente por
-- diseño via el UNIQUE(source, external_ref) — si ya existe, regresa la
-- fila existente en vez de tronar, para que una Edge Function pueda
-- reintentar sin miedo a duplicar.
create function public.award_points(
  p_user_id uuid,
  p_source text,
  p_external_ref text,
  p_points integer,
  p_status text,
  p_occurred_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
) returns public.points_ledger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.points_ledger;
begin
  if p_source not in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste') then
    raise exception 'award_points: source invalida: %', p_source;
  end if;
  if p_status not in ('pendiente', 'confirmado', 'anulado') then
    raise exception 'award_points: status invalido: %', p_status;
  end if;

  insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
  values (p_user_id, p_source, p_external_ref, p_points, p_status, p_occurred_at, coalesce(p_metadata, '{}'::jsonb))
  on conflict (source, external_ref) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row
      from public.points_ledger
      where source = p_source and external_ref = p_external_ref;
  end if;

  return v_row;
end;
$$;

revoke execute on function public.award_points(uuid, text, text, integer, text, timestamptz, jsonb) from public;
revoke execute on function public.award_points(uuid, text, text, integer, text, timestamptz, jsonb) from anon;
revoke execute on function public.award_points(uuid, text, text, integer, text, timestamptz, jsonb) from authenticated;
