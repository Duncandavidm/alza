-- Reportes de MetricKit (crashes, hangs, excepciones de CPU/disco/memoria)
-- que Apple junta en el dispositivo durante ~24h de uso real y entrega una
-- vez al dia via MXMetricManagerSubscriber. Sin esto, un bug silencioso en
-- produccion solo se sabe por una resena negativa — pero tampoco queremos
-- depender de un SDK de terceros (Sentry, Crashlytics, etc.), asi que el
-- JSON nativo de cada reporte se sube tal cual a esta tabla propia y David
-- lo revisa directo en el dashboard de Supabase.
create table public.app_diagnostics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  kind text not null check (kind in ('metric', 'diagnostic')),
  app_version text,
  os_version text,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index app_diagnostics_created_at_idx on public.app_diagnostics (created_at desc);
create index app_diagnostics_kind_idx on public.app_diagnostics (kind);

alter table public.app_diagnostics enable row level security;

-- Solo insertar desde la app, nunca leer/editar/borrar — evita que un
-- usuario vea reportes de otro. El dashboard de Supabase (como owner)
-- bypassa RLS, asi que David si puede revisarlos ahi.
create policy "app_diagnostics_insert_own" on public.app_diagnostics
  for insert with check (auth.uid() = user_id);
