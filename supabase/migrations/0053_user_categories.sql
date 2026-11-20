-- Categorias propias de cada persona (nombre + emoji). Los movimientos
-- guardan el nombre en transactions.category (texto libre), igual que las
-- categorias fijas de la app.
create table public.user_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 30),
  emoji text not null default '🏷️' check (char_length(emoji) between 1 and 16),
  kind text not null default 'gasto' check (kind in ('gasto', 'ingreso', 'ambos')),
  created_at timestamptz not null default now()
);
create unique index user_categories_user_name_idx on public.user_categories (user_id, lower(btrim(name)));
alter table public.user_categories enable row level security;
create policy user_categories_select on public.user_categories for select to authenticated using (user_id = auth.uid());
create policy user_categories_insert on public.user_categories for insert to authenticated with check (user_id = auth.uid());
create policy user_categories_update on public.user_categories for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_categories_delete on public.user_categories for delete to authenticated using (user_id = auth.uid());
