-- Sugerencias/mejoras que los clientes escriben desde la app, para que
-- David las revise directo en el dashboard de Supabase (sin necesidad de
-- una pantalla de admin dentro de la app).
create table public.feedback_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  message text not null check (length(trim(message)) > 0),
  created_at timestamptz not null default now()
);

create index feedback_suggestions_user_id_idx on public.feedback_suggestions (user_id);

alter table public.feedback_suggestions enable row level security;

create policy "feedback_suggestions_all_own" on public.feedback_suggestions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
