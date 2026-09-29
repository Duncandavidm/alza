-- Alza — esquema inicial (nuevo proyecto Supabase, independiente de maday)

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- profiles: un renglon por usuario de auth.users
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- Crea el profile automaticamente cuando se registra un usuario nuevo.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------------
-- helper: mantener updated_at
-- ---------------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- accounts: cuentas financieras que el usuario da de alta a mano
-- ---------------------------------------------------------------------------
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  type text not null check (type in ('checking', 'savings', 'credit_card', 'investment', 'cash', 'loan', 'other')),
  balance numeric(14, 2) not null default 0,
  currency text not null default 'USD',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index accounts_user_id_idx on public.accounts (user_id);

alter table public.accounts enable row level security;

create policy "accounts_all_own" on public.accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger accounts_set_updated_at
  before update on public.accounts
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- transactions: movimientos dentro de una cuenta
-- ---------------------------------------------------------------------------
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  -- positivo = ingreso, negativo = gasto
  amount numeric(14, 2) not null,
  category text,
  description text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index transactions_user_id_idx on public.transactions (user_id);
create index transactions_account_id_idx on public.transactions (account_id);
create index transactions_occurred_at_idx on public.transactions (occurred_at desc);

alter table public.transactions enable row level security;

create policy "transactions_all_own" on public.transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- ai_insights: resultados generados por la Edge Function generate-insights
-- ---------------------------------------------------------------------------
create table public.ai_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default 'general' check (kind in ('general', 'spending', 'saving', 'alert')),
  title text not null,
  body text not null,
  dismissed boolean not null default false,
  created_at timestamptz not null default now()
);

create index ai_insights_user_id_idx on public.ai_insights (user_id);

alter table public.ai_insights enable row level security;

-- El usuario puede leer y marcar como descartados sus propios insights.
-- Solo la Edge Function (service role) los inserta.
create policy "ai_insights_select_own" on public.ai_insights
  for select using (auth.uid() = user_id);

create policy "ai_insights_update_own" on public.ai_insights
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- subscriptions: estado de la suscripcion de Apple, escrito solo por la
-- Edge Function verify-apple-receipt (service role) tras validar con Apple.
-- appAccountToken en la compra de StoreKit = auth.uid() de este usuario.
-- ---------------------------------------------------------------------------
create table public.subscriptions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  product_id text not null,
  status text not null check (status in ('active', 'expired', 'in_grace_period', 'revoked', 'unknown')),
  apple_transaction_id text,
  apple_original_transaction_id text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

create policy "subscriptions_select_own" on public.subscriptions
  for select using (auth.uid() = user_id);

create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute procedure public.set_updated_at();
