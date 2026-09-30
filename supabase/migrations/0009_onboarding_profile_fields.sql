-- Estudio financiero inicial: campos de contexto en el perfil + marca de
-- que ya se completo el onboarding (para que RootView sepa si mostrarlo).
alter table public.profiles
  add column has_variable_income boolean not null default false,
  add column variable_income_notes text,
  add column onboarding_completed_at timestamptz;
