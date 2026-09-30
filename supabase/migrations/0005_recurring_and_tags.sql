-- Transacciones recurrentes (inspirado en "crea transacciones recurrentes
-- para que nunca olvides nada"): gastos/ingresos fijos que el sistema
-- recuerda, similares a gastos_fijos_config del plan original.
create table public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  name text not null,
  amount numeric(14, 2) not null check (amount > 0),
  movement_type text not null check (movement_type in ('ingreso', 'gasto', 'pago_proveedor', 'inversion', 'transferencia')),
  category text,
  day_of_month int not null check (day_of_month between 1 and 28),
  active boolean not null default true,
  last_logged_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recurring_transactions_user_id_idx on public.recurring_transactions (user_id);

alter table public.recurring_transactions enable row level security;

create policy "recurring_transactions_all_own" on public.recurring_transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger recurring_transactions_set_updated_at
  before update on public.recurring_transactions
  for each row execute procedure public.set_updated_at();

-- Etiquetas en movimientos (inspirado en "Buscar con Etiquetas").
alter table public.transactions
  add column tags text[] not null default '{}';

create index transactions_tags_idx on public.transactions using gin (tags);
