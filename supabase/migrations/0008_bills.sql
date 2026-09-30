-- Cuentas por pagar: el diferenciador de Alza. Facturas/recibos pendientes
-- con fecha de vencimiento (distinto de recurring_transactions, que son
-- plantillas fijas mensuales). Cuando el usuario registra un ingreso, la
-- app mira estas + las recurrentes vencidas y aconseja que pagar primero.
create table public.bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  name text not null,
  amount numeric(14, 2) not null check (amount > 0),
  due_date date not null,
  category text,
  movement_type text not null default 'gasto' check (movement_type in ('gasto', 'pago_proveedor')),
  -- prioridad base que el usuario puede ajustar a mano; la IA la usa como
  -- una senal mas, no como la unica.
  priority text not null default 'normal' check (priority in ('critica', 'alta', 'normal', 'baja')),
  status text not null default 'pendiente' check (status in ('pendiente', 'pagada')),
  recurring_transaction_id uuid references public.recurring_transactions (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index bills_user_id_idx on public.bills (user_id);
create index bills_status_idx on public.bills (user_id, status);

alter table public.bills enable row level security;

create policy "bills_all_own" on public.bills
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger bills_set_updated_at
  before update on public.bills
  for each row execute procedure public.set_updated_at();
