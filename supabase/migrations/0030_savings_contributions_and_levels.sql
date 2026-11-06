-- Niveles e insignias (reemplaza "Ahorro verificado" con banco).
--
-- 1) savings_contributions: historial de cada aporte (+) o retiro (-) a
--    una meta de ahorro. Es la base de las reglas anti-trampa de los
--    habitos de ahorro (aporte que "madura" 30 dias sin retiros,
--    constancia semanal, ahorro que cuadra con ingresos - gastos). Es
--    solo de insercion: no se puede editar ni borrar, y `created_at` lo
--    pone siempre el servidor (no se puede fechar un aporte hacia atras).
--
-- 2) points_balances deja de sumar la fuente 'habito': los habitos ahora
--    dan experiencia (niveles e insignias) que NO se canjea, asi que no
--    deben entrar al saldo de puntos canjeables. Las reglas de niveles se
--    calculan en la app (HabitEngine) a partir de los datos del usuario.

create table public.savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  goal_id uuid not null references public.savings_goals (id) on delete cascade,
  amount numeric(14, 2) not null check (amount <> 0),
  created_at timestamptz not null default now()
);

create index savings_contributions_user_id_idx on public.savings_contributions (user_id);
create index savings_contributions_goal_id_idx on public.savings_contributions (goal_id);

alter table public.savings_contributions enable row level security;

create policy "savings_contributions_select_own" on public.savings_contributions
  for select using ((select auth.uid()) = user_id);

-- Solo puede insertar aportes a SUS metas.
create policy "savings_contributions_insert_own" on public.savings_contributions
  for insert with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.savings_goals g
      where g.id = goal_id and g.user_id = (select auth.uid())
    )
  );

-- Sin politicas de update/delete: el historial es inmutable.

-- Historial de aportes existente: un solo aporte por meta con lo que ya
-- tenia ahorrado, fechado en su ultima actualizacion (lo mas conservador).
insert into public.savings_contributions (user_id, goal_id, amount, created_at)
select user_id, id, current_amount, updated_at
from public.savings_goals
where current_amount > 0;

create function public.savings_contributions_force_now()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

create trigger savings_contributions_force_now
  before insert on public.savings_contributions
  for each row execute procedure public.savings_contributions_force_now();

create or replace view public.points_balances
  with (security_invoker = true)
  as
  select
    user_id,
    coalesce(sum(points) filter (where status = 'confirmado' and source <> 'habito'), 0) as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente' and source <> 'habito'), 0) as pending_points
  from public.points_ledger
  group by user_id;
