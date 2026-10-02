-- Metas de ahorro a corto/largo plazo (ej. "Carro nuevo", $15,000, para
-- diciembre): monto objetivo + fecha limite, de donde el cliente calcula
-- la cuota mensual necesaria del lado de Swift (no hace falta guardarla,
-- se recalcula de los otros dos campos).
create table public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  emoji text not null default '🎯',
  target_amount numeric(14, 2) not null check (target_amount > 0),
  target_date date not null,
  current_amount numeric(14, 2) not null default 0 check (current_amount >= 0),
  account_id uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index savings_goals_user_id_idx on public.savings_goals (user_id);

alter table public.savings_goals enable row level security;

create policy "savings_goals_all_own" on public.savings_goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger savings_goals_set_updated_at
  before update on public.savings_goals
  for each row execute procedure public.set_updated_at();
