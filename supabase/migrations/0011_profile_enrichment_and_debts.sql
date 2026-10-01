-- Ampliacion del estudio financiero inicial (inspirado en el prompt que
-- David uso para la version web en Lovable): panorama personal mas
-- completo (edad, estado civil, dependientes, ocupacion, tolerancia al
-- riesgo, metas) + deudas como concepto propio (antes solo existian
-- bills/recurring, pero una tarjeta de credito o un prestamo con interes
-- no encajaba ahi).

alter table public.profiles
  add column age int,
  add column marital_status text
    check (marital_status in ('soltero', 'casado', 'union_libre', 'divorciado', 'viudo')),
  add column dependents_count int,
  add column occupation text,
  add column risk_tolerance text check (risk_tolerance in ('bajo', 'medio', 'alto')),
  add column short_term_goals text[],
  add column long_term_goals text[];

-- ---------------------------------------------------------------------------
-- debts: tarjetas de credito, prestamos, sobregiros — con tasa de interes
-- y estado de mora, para que el consejo de pago (prioritize-payments)
-- pueda tomarlas en cuenta junto a las cuentas por pagar y recurrentes.
-- ---------------------------------------------------------------------------
create table public.debts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  creditor text not null,
  balance numeric(14, 2) not null default 0,
  credit_limit numeric(14, 2),
  interest_rate_monthly numeric(6, 3),
  minimum_payment numeric(14, 2),
  due_date date,
  is_overdue boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'in_restructuring', 'paid_off')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index debts_user_id_idx on public.debts (user_id);

alter table public.debts enable row level security;

create policy "debts_all_own" on public.debts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger debts_set_updated_at
  before update on public.debts
  for each row execute procedure public.set_updated_at();
