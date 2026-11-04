-- "Ahorro verificado" (B2): el usuario se inscribe con un banco
-- patrocinador (consentimiento separado y revocable, SIN guardar el
-- numero de cuenta real — solo un identificador acordado con el banco),
-- pone una meta mensual, y el banco reporta periodicamente si cumplio
-- (por SALDO PROMEDIO del mes, nunca por un deposito puntual). Los
-- puntos quedan 'pendiente' hasta que el reporte del SIGUIENTE periodo
-- confirme que el dinero se quedo ahi la permanencia minima — si se
-- retira antes, se anulan.

create table public.bank_partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null default 'active' check (status in ('active', 'paused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bank_partners enable row level security;

create policy "bank_partners_select_authenticated" on public.bank_partners
  for select to authenticated using (true);

create trigger bank_partners_set_updated_at
  before update on public.bank_partners
  for each row execute procedure public.set_updated_at();

-- La relacion de consentimiento con un banco. `external_account_ref` es
-- un identificador OPACO acordado con el banco (ej. un token que el
-- banco genera y le entrega al usuario para que lo capture aqui) —
-- NUNCA el numero de cuenta real. Revocar el consentimiento no borra el
-- historial, solo detiene futuros reportes (RLS de
-- savings_bank_reports no deja que un cliente vea nada igual, solo
-- afecta que la reconciliacion ya no lo procese).
create table public.sponsored_savings_enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  bank_partner_id uuid not null references public.bank_partners (id) on delete cascade,
  external_account_ref text not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  consent_at timestamptz not null default now(),
  consent_revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bank_partner_id, external_account_ref)
);

create index sponsored_savings_enrollments_user_id_idx on public.sponsored_savings_enrollments (user_id);

alter table public.sponsored_savings_enrollments enable row level security;

create policy "sponsored_savings_enrollments_all_own" on public.sponsored_savings_enrollments
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create trigger sponsored_savings_enrollments_set_updated_at
  before update on public.sponsored_savings_enrollments
  for each row execute procedure public.set_updated_at();

-- La meta de un mes especifico dentro de una inscripcion.
-- `period_month` siempre es el primer dia del mes.
create table public.sponsored_savings_goals (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.sponsored_savings_enrollments (id) on delete cascade,
  period_month date not null,
  target_amount numeric(14, 2) not null check (target_amount > 0),
  status text not null default 'active' check (status in ('active', 'met', 'missed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (enrollment_id, period_month)
);

create index sponsored_savings_goals_enrollment_idx on public.sponsored_savings_goals (enrollment_id);

alter table public.sponsored_savings_goals enable row level security;

-- El usuario puede crear/ver/editar sus metas, pero solo a traves de su
-- propia inscripcion (chequeado con un EXISTS, no hay user_id directo
-- en esta tabla para no duplicarlo).
create policy "sponsored_savings_goals_all_own" on public.sponsored_savings_goals
  for all
  using (exists (
    select 1 from public.sponsored_savings_enrollments e
    where e.id = sponsored_savings_goals.enrollment_id and e.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.sponsored_savings_enrollments e
    where e.id = sponsored_savings_goals.enrollment_id and e.user_id = (select auth.uid())
  ));

create trigger sponsored_savings_goals_set_updated_at
  before update on public.sponsored_savings_goals
  for each row execute procedure public.set_updated_at();

-- Reportes del banco (o del mock) — mesa de trabajo de la
-- reconciliacion, igual que card_transactions en la Fase 1: SI se
-- actualiza, a diferencia del ledger. `avg_balance` es el saldo
-- PROMEDIO del periodo que reporta el banco — nunca un snapshot ni un
-- deposito puntual, ese es el mecanismo antitrampa real (vive en lo que
-- el banco esta dispuesto a certificar, no en logica nuestra).
create table public.savings_bank_reports (
  id uuid primary key default gen_random_uuid(),
  bank_partner_id uuid not null references public.bank_partners (id) on delete cascade,
  external_account_ref text not null,
  period_month date not null,
  avg_balance numeric(14, 2) not null check (avg_balance >= 0),
  source text not null,

  match_status text not null default 'pending_match'
    check (match_status in ('pending_match', 'matched', 'unmatched')),
  enrollment_id uuid references public.sponsored_savings_enrollments (id) on delete set null,
  goal_id uuid references public.sponsored_savings_goals (id) on delete set null,
  points_awarded integer,
  retention_resolved_at timestamptz,
  match_note text,

  provided_at timestamptz not null default now(),
  reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (bank_partner_id, external_account_ref, period_month)
);

create index savings_bank_reports_pending_idx on public.savings_bank_reports (match_status)
  where match_status = 'pending_match';
create index savings_bank_reports_enrollment_idx on public.savings_bank_reports (enrollment_id);

alter table public.savings_bank_reports enable row level security;

-- Nadie de authenticated/anon ve esto directo (ni filtrado por
-- usuario): la app lee el resultado via points_ledger/goal.status, no
-- el reporte crudo del banco. Solo la service role (reconciliacion /
-- panel admin).

create trigger savings_bank_reports_set_updated_at
  before update on public.savings_bank_reports
  for each row execute procedure public.set_updated_at();

insert into public.points_rules (source, key, value) values
  ('ahorro', 'min_retention_days', '30'::jsonb),
  ('ahorro', 'withdrawal_threshold_fraction', '0.5'::jsonb)
on conflict (source, key) do nothing;
