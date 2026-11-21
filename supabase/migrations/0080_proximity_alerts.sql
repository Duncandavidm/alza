-- 0080: avisos por cercania (lado del panel). La app los usara en una
-- version futura: "Estás cerca de Café La Esquina: tienes 10% de
-- descuento". Aqui solo se guardan las ubicaciones y los ajustes.
--
-- Decisiones: radio 300 m; solo a quien ya tiene un descuento o cupon
-- en ese comercio; maximo 1 aviso por comercio cada 7 dias y 2 por dia;
-- nada entre las 21:00 y las 8:00. La ubicacion de la persona nunca sale
-- de su iPhone: el servidor solo sabe donde estan los locales.

alter table public.partner_merchants
  add column if not exists latitude double precision check (latitude between -90 and 90),
  add column if not exists longitude double precision check (longitude between -180 and 180),
  add column if not exists proximity_alerts boolean not null default true;

alter table public.merchant_branches
  add column if not exists latitude double precision check (latitude between -90 and 90),
  add column if not exists longitude double precision check (longitude between -180 and 180);

insert into public.app_config (key, value) values
  ('proximity_alerts_enabled', 'true'::jsonb),
  ('proximity_radius_m', '300'::jsonb),
  ('proximity_cooldown_days', '7'::jsonb),
  ('proximity_daily_max', '2'::jsonb),
  ('proximity_quiet_start_hour', '21'::jsonb),
  ('proximity_quiet_end_hour', '8'::jsonb),
  ('proximity_only_with_benefit', 'true'::jsonb)
on conflict (key) do nothing;

-- Registro sin coordenadas: que aviso se mostro y si se abrio, para
-- medir cuantos canjes trae cada aviso (argumento de venta al comercio).
create table if not exists public.proximity_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  merchant_id uuid not null references public.partner_merchants(id) on delete cascade,
  branch_id uuid references public.merchant_branches(id) on delete set null,
  kind text not null check (kind in ('shown', 'opened')),
  created_at timestamptz not null default now()
);
create index if not exists proximity_events_merchant_idx on public.proximity_events (merchant_id, created_at desc);
create index if not exists proximity_events_user_idx on public.proximity_events (user_id, created_at desc);

alter table public.proximity_events enable row level security;
drop policy if exists proximity_events_insert_own on public.proximity_events;
create policy proximity_events_insert_own on public.proximity_events
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists proximity_events_select_own on public.proximity_events;
create policy proximity_events_select_own on public.proximity_events
  for select to authenticated using (user_id = (select auth.uid()));
grant select, insert on public.proximity_events to authenticated;
