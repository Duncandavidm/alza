-- "Tarjeta en comercios aliados": el usuario vincula una tarjeta (solo
-- marca + ultimos 4 + alias — NUNCA numero completo, CVV ni vencimiento,
-- ver README_SECURITY.md), y cuando paga en un comercio aliado, el
-- comercio reporta sus ventas con tarjeta y el sistema cruza por
-- ultimos4+marca para encontrar que usuario fue. Ambiguo (mas de un
-- usuario posible) = NO se asignan puntos, queda para revision.

-- Tarjetas vinculadas por el usuario. Dato liviano a proposito: nunca
-- deberia poder reconstruirse una tarjeta real a partir de esto.
create table public.linked_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  brand text not null check (brand in ('visa', 'mastercard', 'amex', 'other')),
  last4 text not null check (last4 ~ '^[0-9]{4}$'),
  alias text not null,
  status text not null default 'active' check (status in ('active', 'paused', 'removed')),
  consent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index linked_cards_user_id_idx on public.linked_cards (user_id);
-- La usa la reconciliacion para encontrar candidatos por ultimos4+marca,
-- solo entre tarjetas activas.
create index linked_cards_brand_last4_idx on public.linked_cards (brand, last4) where status = 'active';

alter table public.linked_cards enable row level security;

create policy "linked_cards_all_own" on public.linked_cards
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create trigger linked_cards_set_updated_at
  before update on public.linked_cards
  for each row execute procedure public.set_updated_at();

-- Comercios aliados y sus sucursales. Se administran desde el panel web
-- (Fase 4) o el Table Editor mientras tanto — la app solo LEE.
create table public.partner_merchants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  ruc text not null unique,
  status text not null default 'active' check (status in ('active', 'paused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.partner_merchant_branches (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.partner_merchants (id) on delete cascade,
  sucursal text not null,
  name text,
  unique (merchant_id, sucursal)
);

-- Oferta activa del comercio: porcentaje en puntos, o puntos fijos con
-- compra minima. `budget_spent_points` es un contador que la
-- reconciliacion incrementa atomicamente — al llegar a
-- budget_total_points, la oferta deja de dar puntos nuevos.
create table public.partner_merchant_offers (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.partner_merchants (id) on delete cascade,
  offer_type text not null check (offer_type in ('percent', 'fixed')),
  -- percent: puntos por cada dolar (ej. 5 = 5 puntos por dolar).
  -- fixed: puntos fijos por compra que alcance min_amount.
  value numeric(10, 4) not null check (value > 0),
  min_amount numeric(14, 2),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  budget_total_points integer check (budget_total_points is null or budget_total_points > 0),
  budget_spent_points integer not null default 0,
  status text not null default 'active' check (status in ('active', 'paused', 'budget_exhausted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index partner_merchant_offers_merchant_idx on public.partner_merchant_offers (merchant_id);
create index partner_merchant_offers_active_idx on public.partner_merchant_offers (merchant_id, status)
  where status = 'active';

alter table public.partner_merchants enable row level security;
alter table public.partner_merchant_branches enable row level security;
alter table public.partner_merchant_offers enable row level security;

-- Lectura publica para cualquier autenticado (son los datos de "Ofertas
-- cerca"), escritura solo service role (panel admin / Table Editor).
create policy "partner_merchants_select_authenticated" on public.partner_merchants
  for select to authenticated using (true);
create policy "partner_merchant_branches_select_authenticated" on public.partner_merchant_branches
  for select to authenticated using (true);
create policy "partner_merchant_offers_select_authenticated" on public.partner_merchant_offers
  for select to authenticated using (true);

create trigger partner_merchants_set_updated_at
  before update on public.partner_merchants
  for each row execute procedure public.set_updated_at();
create trigger partner_merchant_offers_set_updated_at
  before update on public.partner_merchant_offers
  for each row execute procedure public.set_updated_at();

-- Compras con tarjeta reportadas por un proveedor (ver
-- ProveedorTransaccionesTarjeta en la Edge Function) y su estado de
-- cruce contra linked_cards. A diferencia de points_ledger, esta tabla
-- SI se actualiza — es la mesa de trabajo de la reconciliacion, no el
-- libro contable (eso es points_ledger, via award_points).
create table public.card_transactions (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_transaction_id text not null,

  -- Lo que reporto el proveedor/comercio, tal cual.
  merchant_ruc text not null,
  branch text,
  amount numeric(14, 2) not null check (amount > 0),
  occurred_at timestamptz not null,
  card_last4 text not null check (card_last4 ~ '^[0-9]{4}$'),
  card_brand text not null check (card_brand in ('visa', 'mastercard', 'amex', 'other')),
  report_status text not null check (report_status in ('authorized', 'settled', 'reversed')),

  -- Resultado del cruce — nulos hasta que la reconciliacion corra.
  match_status text not null default 'pending_match'
    check (match_status in ('pending_match', 'matched', 'unmatched', 'ambiguous')),
  user_id uuid references auth.users (id) on delete set null,
  linked_card_id uuid references public.linked_cards (id) on delete set null,
  merchant_id uuid references public.partner_merchants (id) on delete set null,
  transaction_id uuid references public.transactions (id) on delete set null,
  points_awarded integer,
  match_note text,

  ingested_at timestamptz not null default now(),
  reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (provider, provider_transaction_id)
);

create index card_transactions_match_status_idx on public.card_transactions (match_status)
  where match_status = 'pending_match';
create index card_transactions_user_id_idx on public.card_transactions (user_id);
create index card_transactions_merchant_id_idx on public.card_transactions (merchant_id);
create index card_transactions_transaction_id_idx on public.card_transactions (transaction_id);

alter table public.card_transactions enable row level security;

-- El usuario solo ve SUS compras ya emparejadas — las 'pending_match'/
-- 'unmatched'/'ambiguous' (user_id null) no las ve nadie de
-- authenticated/anon, solo el panel admin via service role.
create policy "card_transactions_select_own" on public.card_transactions
  for select
  using ((select auth.uid()) = user_id);

create trigger card_transactions_set_updated_at
  before update on public.card_transactions
  for each row execute procedure public.set_updated_at();

-- Cuenta de MonAvi a la que se atribuye un gasto detectado por esta
-- tarjeta (si es null, la reconciliacion usa la cuenta mas antigua del
-- usuario como fallback — mismo criterio que `defaultAccountId` en
-- DayJournalViewModel).
alter table public.linked_cards
  add column account_id uuid references public.accounts (id) on delete set null;
