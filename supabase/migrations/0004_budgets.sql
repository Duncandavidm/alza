-- Presupuestos por categoria (inspirado en MonAi): limite de gasto semanal o
-- mensual por categoria, con progreso visible en "Hoy".
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category text not null,
  period text not null check (period in ('weekly', 'monthly')),
  limit_amount numeric(14, 2) not null check (limit_amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, category, period)
);

create index budgets_user_id_idx on public.budgets (user_id);

alter table public.budgets enable row level security;

create policy "budgets_all_own" on public.budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger budgets_set_updated_at
  before update on public.budgets
  for each row execute procedure public.set_updated_at();
