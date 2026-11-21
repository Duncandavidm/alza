-- 1.0.3: solo cashback y descuentos (los puntos se dejan de usar), categorias
-- de comercio administrables, comercios ocultos hasta publicarlos, referidos
-- que dan cashback, cupones por buenos habitos con reglas, salud financiera
-- por cliente, liquidacion a comercios y reinicio de cuentas desde el panel.
--
-- Compatibilidad: la moneda 'puntos' sigue siendo valida en la base (la usan
-- la cuenta de revision de Apple y el comercio de prueba mientras 1.0.1 esta
-- en revision); simplemente ya no se ofrece en el panel ni en la app 1.0.3.

-- ---------------------------------------------------------------------
-- 1) Categorias de comercio (las crea el panel)
-- ---------------------------------------------------------------------
create table if not exists public.merchant_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 2 and 60),
  emoji text check (emoji is null or char_length(emoji) <= 8),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.merchant_categories enable row level security;
drop policy if exists merchant_categories_select on public.merchant_categories;
create policy merchant_categories_select on public.merchant_categories for select using (true);

insert into public.merchant_categories (name, emoji, sort_order) values
  ('Restaurantes y cafés', '🍽️', 1),
  ('Supermercados', '🛒', 2),
  ('Salud y farmacias', '💊', 3),
  ('Belleza y cuidado personal', '💅', 4),
  ('Ropa y accesorios', '👗', 5),
  ('Tecnología y electrónica', '📱', 6),
  ('Hogar y ferretería', '🏠', 7),
  ('Entretenimiento', '🎬', 8),
  ('Mascotas', '🐾', 9),
  ('Servicios', '🧰', 10)
on conflict (name) do nothing;
insert into public.merchant_categories (name, sort_order)
select distinct trim(category), 50 from public.partner_merchants
where nullif(trim(category), '') is not null
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- 2) Comercios: nacen ocultos; el panel los publica
-- ---------------------------------------------------------------------
alter table public.partner_merchants alter column status set default 'paused';

-- ---------------------------------------------------------------------
-- 3) Referidos: cashback en vez de puntos
-- ---------------------------------------------------------------------
alter table public.points_ledger drop constraint if exists points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check check (source in (
  'factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje', 'canje_puntos', 'marca', 'marca_puntos',
  'bono', 'bono_puntos', 'referido_puntos', 'referido'));

insert into public.app_config (key, value) values
  ('referral_cashback_referrer_cents', '100'::jsonb),
  ('referral_cashback_referee_cents', '50'::jsonb)
on conflict (key) do nothing;

create or replace view public.points_balances as
 select user_id,
    coalesce(sum(points) filter (where status = 'confirmado' and source = any (array['factura','tarjeta','ajuste','canje','marca','bono','referido'])), 0)::bigint as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente' and source = any (array['factura','tarjeta','ajuste','canje','marca','bono','referido'])), 0)::bigint as pending_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source = any (array['habito','canje_puntos','marca_puntos','bono_puntos','referido_puntos'])), 0)::bigint as habit_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source = 'habito' and points > 0), 0)::bigint as habit_points_earned
   from public.points_ledger
  group by user_id;

create or replace function public.reward_balance(p_user_id uuid, p_currency text)
 returns integer
 language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(sum(points), 0)::integer
  from public.points_ledger
  where user_id = p_user_id
    and status = 'confirmado'
    and source = any (
      case when p_currency = 'puntos'
        then array['habito', 'canje_puntos']
        else array['factura', 'tarjeta', 'ajuste', 'canje', 'marca', 'bono', 'referido']
      end
    );
$function$;

create or replace function public.reward_referral(p_referee uuid)
 returns boolean
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  r public.referrals%rowtype;
  v_recent int;
  v_referrer_cents int := coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referrer_cents'), 100);
  v_referee_cents int := coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referee_cents'), 50);
begin
  select * into r from public.referrals where referee_id = p_referee and status = 'pendiente' for update;
  if not found then
    return false;
  end if;
  -- Antifraude: el invitado tiene que tener una factura verificada por la DGI.
  if not exists (select 1 from public.dgi_receipts where user_id = p_referee and status = 'confirmada') then
    return false;
  end if;

  if v_referee_cents > 0 then
    insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
    values (r.referee_id, 'referido', 'referido:' || r.id || ':invitado', v_referee_cents, 'confirmado',
            jsonb_build_object('referral', r.id, 'role', 'invitado'))
    on conflict (source, external_ref) do nothing;
  end if;

  select count(*) into v_recent from public.referrals
  where referrer_id = r.referrer_id and status = 'premiado' and rewarded_at > now() - interval '30 days';

  if v_recent < 10 and v_referrer_cents > 0 then
    insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
    values (r.referrer_id, 'referido', 'referido:' || r.id || ':invita', v_referrer_cents, 'confirmado',
            jsonb_build_object('referral', r.id, 'role', 'invita'))
    on conflict (source, external_ref) do nothing;
    update public.referrals set status = 'premiado', rewarded_at = now() where id = r.id;
  else
    update public.referrals set status = 'sin_premio', rewarded_at = now() where id = r.id;
  end if;
  return true;
end $function$;

-- points_earned: ahora centavos de cashback (la 1.0.3 lo muestra como $).
create or replace function public.my_referral_summary()
 returns table(code text, invited integer, rewarded integer, pending integer, points_earned integer, can_apply_code boolean, applied_code text)
 language plpgsql security definer set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  return query
  select public.my_referral_code(),
    (select count(*)::int from public.referrals where referrer_id = v_user),
    (select count(*)::int from public.referrals where referrer_id = v_user and status = 'premiado'),
    (select count(*)::int from public.referrals where referrer_id = v_user and status = 'pendiente'),
    (select coalesce(sum(points), 0)::int from public.points_ledger where user_id = v_user and source in ('referido', 'referido_puntos')),
    (not exists (select 1 from public.referrals where referee_id = v_user)
       and (select created_at from auth.users where id = v_user) > now() - interval '7 days'),
    (select rf.code from public.referrals rf where rf.referee_id = v_user);
end $function$;

create or replace function public.referral_reward_cents()
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'referrer', coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referrer_cents'), 100),
    'referee', coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referee_cents'), 50));
$$;
grant execute on function public.referral_reward_cents() to authenticated;

-- ---------------------------------------------------------------------
-- 4) Salud financiera de cada persona (mes calendario, hora de Panama)
-- ---------------------------------------------------------------------
-- Todo sale de lo que la persona registra en la app (ingresos, gastos,
-- presupuestos, facturas). Para que no se pueda "ganar" dejando de anotar
-- gastos, las reglas de cupones piden un minimo de dias anotados.
create or replace function public.financial_month_metrics(p_user_id uuid, p_month date)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
with bounds as (
  select (date_trunc('month', p_month::timestamp) at time zone 'America/Panama') as since,
         ((date_trunc('month', p_month::timestamp) + interval '1 month') at time zone 'America/Panama') as until
),
tx as (
  select t.amount, t.movement_type, t.category, t.created_at
  from public.transactions t, bounds b
  where t.user_id = p_user_id and t.occurred_at >= b.since and t.occurred_at < b.until
),
totals as (
  select coalesce(sum(amount) filter (where movement_type = 'ingreso' and amount > 0), 0) as income,
         coalesce(sum(abs(amount)) filter (where movement_type <> 'ingreso'), 0) as expenses,
         count(distinct (created_at at time zone 'America/Panama')::date) as logged_days,
         count(*) filter (where movement_type <> 'ingreso') as expense_count
  from tx
),
budget_check as (
  select b.id, b.limit_amount,
         coalesce((select sum(abs(t.amount)) from tx t where t.movement_type <> 'ingreso' and t.category = b.category), 0) as spent
  from public.budgets b
  where b.user_id = p_user_id and b.period = 'monthly'
),
receipts as (
  select count(*) as n from public.dgi_receipts r, bounds b
  where r.user_id = p_user_id and r.status in ('pendiente', 'confirmada')
    and r.scanned_at >= b.since and r.scanned_at < b.until
),
overdue as (
  select count(*) as n from public.bills
  where user_id = p_user_id and status = 'pendiente'
    and due_date < least((select until from bounds)::date, (now() at time zone 'America/Panama')::date)
),
m as (
  select t.income, t.expenses, t.logged_days, t.expense_count,
         case when t.income > 0 then round(100 * (t.income - t.expenses) / t.income, 1) end as savings_rate,
         (select count(*) from budget_check) as budgets,
         (select count(*) from budget_check where spent <= limit_amount) as budgets_met,
         (select n from receipts) as receipts,
         (select n from overdue) as overdue_bills
  from totals t
)
select jsonb_build_object(
  'month', to_char(p_month, 'YYYY-MM'),
  'income', round(income, 2),
  'expenses', round(expenses, 2),
  'savings_rate', savings_rate,
  'logged_days', logged_days,
  'expense_count', expense_count,
  'budgets', budgets,
  'budgets_met', budgets_met,
  'receipts', receipts,
  'overdue_bills', overdue_bills,
  -- Puntaje 0-100: ahorro (40), presupuestos (20), constancia (20),
  -- facturas (10) y cuentas al dia (10).
  'score', round(
      40 * least(greatest(coalesce(savings_rate, 0), 0), 30) / 30
    + 20 * case when budgets > 0 then budgets_met::numeric / budgets else 0 end
    + 20 * least(logged_days, 20)::numeric / 20
    + 10 * least(receipts, 2)::numeric / 2
    + 10 * case when overdue_bills = 0 then 1 else 0 end)
)
from m;
$$;
revoke all on function public.financial_month_metrics(uuid, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Cupones por buenos habitos (MonAvi le paga al comercio)
-- ---------------------------------------------------------------------
-- El cupon es un reward_item "de cupon" (audience 'cupon'): no sale en el
-- catalogo ni en los descuentos, solo llega a quien cumple la regla, como
-- regalo (source 'regalo', con su codigo para caja).
alter table public.reward_items
  add column if not exists audience text not null default 'catalogo';
alter table public.reward_items drop constraint if exists reward_items_audience_check;
alter table public.reward_items add constraint reward_items_audience_check check (audience in ('catalogo', 'cupon'));

drop policy if exists reward_items_select_active on public.reward_items;
create policy reward_items_select_active on public.reward_items
  for select using (
    status = 'active' and not free_benefit and audience = 'catalogo'
    and exists (select 1 from public.partner_merchants m where m.id = reward_items.merchant_id and m.status = 'active')
  );

create table if not exists public.habit_coupon_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 120),
  reward_item_id uuid not null references public.reward_items(id) on delete restrict,
  rule_type text not null check (rule_type in ('ahorro_ingresos', 'meta_a_tiempo', 'presupuestos', 'dias_registrados', 'salud_financiera')),
  -- threshold: % de ahorro, dias, puntaje o monto minimo de la meta.
  threshold numeric not null default 0,
  min_logged_days integer not null default 15 check (min_logged_days between 0 and 31),
  max_coupons integer check (max_coupons is null or max_coupons > 0),
  expires_days integer not null default 30 check (expires_days between 1 and 365),
  message text check (message is null or char_length(message) <= 300),
  status text not null default 'active' check (status in ('active', 'paused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.habit_coupon_rules enable row level security;

create table if not exists public.habit_coupon_grants (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references public.habit_coupon_rules(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  period_key text not null,
  redemption_id uuid references public.reward_redemptions(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (rule_id, user_id, period_key)
);
alter table public.habit_coupon_grants enable row level security;
create index if not exists habit_coupon_grants_user_idx on public.habit_coupon_grants (user_id);

-- Para el panel: el mes pasado y el actual de una persona.
create or replace function public.admin_financial_health(p_user_id uuid)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'last_month', public.financial_month_metrics(p_user_id, ((now() at time zone 'America/Panama') - interval '1 month')::date),
    'this_month', public.financial_month_metrics(p_user_id, (now() at time zone 'America/Panama')::date),
    'goals', coalesce((select jsonb_agg(jsonb_build_object('name', g.name, 'target', g.target_amount, 'current', g.current_amount,
                                                          'target_date', g.target_date) order by g.created_at)
                       from public.savings_goals g where g.user_id = p_user_id), '[]'::jsonb),
    'coupons', (select count(*) from public.habit_coupon_grants c where c.user_id = p_user_id));
$$;
revoke all on function public.admin_financial_health(uuid) from public, anon, authenticated;

-- Texto de la regla ("por ahorrar el 20% de tus ingresos").
create or replace function public.habit_rule_reason(p_rule public.habit_coupon_rules)
returns text
language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case p_rule.rule_type
    when 'ahorro_ingresos' then 'por ahorrar el ' || rtrim(to_char(p_rule.threshold, 'FM999990.##'), '.') || '% de tus ingresos en el mes'
    when 'meta_a_tiempo' then 'por cumplir una meta de ahorro a tiempo'
    when 'presupuestos' then 'por cumplir todos tus presupuestos del mes'
    when 'dias_registrados' then 'por anotar tus movimientos ' || trim(to_char(p_rule.threshold, 'FM990')) || ' días del mes'
    else 'por tener una salud financiera de ' || trim(to_char(p_rule.threshold, 'FM990')) || ' puntos o más'
  end;
$$;

-- Corre a diario (award-habit-points). Las reglas mensuales miran el mes
-- pasado completo (se entregan desde el dia 1); "meta a tiempo" se revisa
-- cada dia. Devuelve lo emitido para mandar el push.
create or replace function public.issue_habit_coupons()
returns table(user_id uuid, redemption_id uuid, rule_name text, coupon_name text, merchant text, reason text, expires_at timestamptz, image_url text)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
#variable_conflict use_column
declare
  v_rule public.habit_coupon_rules;
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_month date := ((now() at time zone 'America/Panama') - interval '1 month')::date;
  v_period text := to_char(((now() at time zone 'America/Panama') - interval '1 month'), 'YYYY-MM');
  v_candidate record;
  v_issued integer;
  v_redemption uuid;
  v_metrics jsonb;
  v_ok boolean;
begin
  for v_rule in select * from public.habit_coupon_rules where status = 'active' order by created_at loop
    select * into v_item from public.reward_items where id = v_rule.reward_item_id;
    select * into v_merchant from public.partner_merchants where id = v_item.merchant_id;
    continue when v_item.id is null or v_merchant.id is null or v_merchant.status <> 'active';

    select count(*) into v_issued from public.habit_coupon_grants g where g.rule_id = v_rule.id;

    for v_candidate in
      select u.id as uid,
             case when v_rule.rule_type = 'meta_a_tiempo' then g.id::text else v_period end as period_key,
             g.name as goal_name
      from auth.users u
      left join public.savings_goals g
        on v_rule.rule_type = 'meta_a_tiempo' and g.user_id = u.id
       and g.current_amount >= g.target_amount and g.target_amount >= greatest(v_rule.threshold, 1)
       and (g.target_date is null or (now() at time zone 'America/Panama')::date <= g.target_date)
       and g.created_at <= now() - interval '30 days'
      where (v_rule.rule_type <> 'meta_a_tiempo' or g.id is not null)
        and (u.banned_until is null or u.banned_until < now())
    loop
      exit when v_rule.max_coupons is not null and v_issued >= v_rule.max_coupons;
      continue when exists (select 1 from public.habit_coupon_grants x
                            where x.rule_id = v_rule.id and x.user_id = v_candidate.uid and x.period_key = v_candidate.period_key);

      v_metrics := public.financial_month_metrics(v_candidate.uid, v_month);
      v_ok := (v_metrics->>'logged_days')::int >= v_rule.min_logged_days and case v_rule.rule_type
        when 'ahorro_ingresos' then (v_metrics->>'income')::numeric > 0
                                 and coalesce((v_metrics->>'savings_rate')::numeric, 0) >= v_rule.threshold
        when 'presupuestos' then (v_metrics->>'budgets')::int >= greatest(v_rule.threshold, 1)
                              and (v_metrics->>'budgets_met')::int = (v_metrics->>'budgets')::int
        when 'dias_registrados' then (v_metrics->>'logged_days')::int >= v_rule.threshold
        when 'salud_financiera' then (v_metrics->>'score')::numeric >= v_rule.threshold
        when 'meta_a_tiempo' then true
        else false end;
      -- "Meta a tiempo" no depende del mes: el minimo de dias se mide en
      -- el mes en curso.
      if v_rule.rule_type = 'meta_a_tiempo' then
        v_ok := (public.financial_month_metrics(v_candidate.uid, (now() at time zone 'America/Panama')::date)->>'logged_days')::int
                >= least(v_rule.min_logged_days, extract(day from (now() at time zone 'America/Panama'))::int);
      end if;
      continue when not v_ok;

      insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, status,
          expires_at, currency, source, gift_message)
      values (v_candidate.uid, v_item.id, v_item.merchant_id, v_item.points_cost, public.new_redemption_code(), 'emitido',
          now() + make_interval(days => v_rule.expires_days), 'cashback', 'regalo',
          coalesce(v_rule.message, '¡Felicidades! Te lo ganaste ' || public.habit_rule_reason(v_rule) || '.'))
      returning id into v_redemption;

      insert into public.habit_coupon_grants (rule_id, user_id, period_key, redemption_id)
      values (v_rule.id, v_candidate.uid, v_candidate.period_key, v_redemption);
      v_issued := v_issued + 1;

      user_id := v_candidate.uid;
      redemption_id := v_redemption;
      rule_name := v_rule.name;
      coupon_name := v_item.name;
      merchant := v_merchant.name;
      reason := public.habit_rule_reason(v_rule);
      expires_at := now() + make_interval(days => v_rule.expires_days);
      image_url := coalesce(v_item.photo_url, v_merchant.logo_url);
      return next;
    end loop;
  end loop;
end $$;
revoke all on function public.issue_habit_coupons() from public, anon, authenticated;

-- Para la app: los cupones que se pueden ganar y como va la persona.
create or replace function public.my_habit_coupons()
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  with me as (select auth.uid() as uid),
  now_m as (select public.financial_month_metrics((select uid from me), (now() at time zone 'America/Panama')::date) as m)
  select jsonb_build_object(
    'this_month', (select m from now_m),
    'rules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'reason', public.habit_rule_reason(r),
        'rule_type', r.rule_type,
        'threshold', r.threshold,
        'min_logged_days', r.min_logged_days,
        'coupon', ri.name,
        'merchant', pm.name,
        'merchant_logo_url', pm.logo_url,
        'photo_url', ri.photo_url,
        'earned_count', (select count(*) from public.habit_coupon_grants g where g.rule_id = r.id and g.user_id = (select uid from me))
      ) order by r.created_at)
      from public.habit_coupon_rules r
      join public.reward_items ri on ri.id = r.reward_item_id
      join public.partner_merchants pm on pm.id = ri.merchant_id
      where r.status = 'active' and pm.status = 'active'
        and (r.max_coupons is null or (select count(*) from public.habit_coupon_grants g where g.rule_id = r.id) < r.max_coupons)
    ), '[]'::jsonb)
  )
  where (select uid from me) is not null;
$$;
revoke all on function public.my_habit_coupons() from public, anon;
grant execute on function public.my_habit_coupons() to authenticated;

-- Liquidacion: cupones de habitos usados en caja por comercio y mes (lo que
-- MonAvi le debe a cada comercio).
create or replace function public.habit_coupon_settlement(p_months integer default 6)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.month desc, x.merchant), '[]'::jsonb)
  from (
    select to_char(date_trunc('month', rr.delivered_at at time zone 'America/Panama'), 'YYYY-MM') as month,
           pm.id as merchant_id, pm.name as merchant,
           count(*) as delivered,
           round(sum(rr.points_cost) / 100.0, 2) as amount_usd,
           (select count(*) from public.habit_coupon_grants g2
              join public.reward_redemptions r2 on r2.id = g2.redemption_id
             where r2.merchant_id = pm.id and r2.status = 'emitido' and r2.expires_at >= now()) as outstanding
    from public.habit_coupon_grants g
    join public.reward_redemptions rr on rr.id = g.redemption_id
    join public.partner_merchants pm on pm.id = rr.merchant_id
    where rr.status = 'entregado'
      and rr.delivered_at >= date_trunc('month', now()) - make_interval(months => greatest(p_months, 1))
    group by 1, pm.id, pm.name
  ) x;
$$;
revoke all on function public.habit_coupon_settlement(integer) from public, anon, authenticated;

-- Los cupones de habitos no avisan "ya te alcanza" (no se compran).
create or replace function public.reward_unlocks_to_notify()
 returns table(user_id uuid, items jsonb)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
begin
  delete from public.reward_unlock_notifications n
  using public.reward_items ri, public.partner_merchants pm
  where ri.id = n.reward_item_id
    and pm.id = ri.merchant_id
    and public.reward_balance(n.user_id, pm.reward_currency) < ri.points_cost;

  return query
  with users_with_tokens as (
    select distinct t.user_id from public.device_push_tokens t
  ),
  affordable as (
    select u.user_id, ri.id as item_id, ri.name, pm.name as merchant, ri.points_cost, pm.reward_currency
    from users_with_tokens u
    cross join public.reward_items ri
    join public.partner_merchants pm on pm.id = ri.merchant_id
    where ri.status = 'active' and pm.status = 'active' and not ri.free_benefit and ri.audience = 'catalogo'
      and public.reward_balance(u.user_id, pm.reward_currency) >= ri.points_cost
      and not exists (
        select 1 from public.reward_unlock_notifications n
        where n.user_id = u.user_id and n.reward_item_id = ri.id
      )
  )
  select a.user_id,
         jsonb_agg(jsonb_build_object(
           'id', a.item_id, 'name', a.name, 'merchant', a.merchant,
           'cost', a.points_cost, 'currency', a.reward_currency
         ) order by a.points_cost desc)
  from affordable a
  group by a.user_id;
end;
$function$;

-- ---------------------------------------------------------------------
-- 6) Push personalizado de un comercio (aliado nuevo o promocion)
-- ---------------------------------------------------------------------
-- Para cada persona: el descuento gratis del comercio (si tiene) y el
-- premio mas barato con cuanto cashback le falta, o si ya le alcanza.
create or replace function public.merchant_push_for_users(p_merchant_id uuid, p_user_ids uuid[])
returns table(user_id uuid, title text, body text, image_url text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  with m as (select * from public.partner_merchants where id = p_merchant_id),
  benefit as (
    select ri.name from public.reward_items ri, m
    where ri.merchant_id = m.id and ri.status = 'active' and ri.free_benefit
    order by ri.sort_order, ri.created_at limit 1
  ),
  product as (
    select ri.name, ri.points_cost from public.reward_items ri, m
    where ri.merchant_id = m.id and ri.status = 'active' and not ri.free_benefit and ri.audience = 'catalogo'
    order by ri.points_cost limit 1
  ),
  people as (
    select u as uid, public.reward_balance(u, 'cashback') as balance from unnest(p_user_ids) u
  )
  select p.uid,
         case when (select name from benefit) is not null
              then 'Tienes ' || (select name from benefit) || ' en ' || m.name || ' 🎉'
              else m.name || ' ya está en MonAvi 🎉' end,
         concat_ws(' ',
           case when (select name from benefit) is not null
                then 'Por ser de MonAvi. Escanea tu factura fiscal y gana cashback también.' end,
           case when (select name from product) is null then null
                when p.balance >= (select points_cost from product)
                then '¡Ya te alcanza para ' || (select name from product) || ' con tu cashback! Reclámalo en la app.'
                else 'Te faltan $' || trim(to_char(((select points_cost from product) - p.balance) / 100.0, 'FM999990.00'))
                     || ' de cashback para ' || (select name from product) || '.' end),
         m.logo_url
  from people p, m;
$$;
revoke all on function public.merchant_push_for_users(uuid, uuid[]) from public, anon, authenticated;

alter table public.push_campaigns add column if not exists merchant_id uuid references public.partner_merchants(id) on delete set null;

-- ---------------------------------------------------------------------
-- 7) Reiniciar una cuenta desde el panel (deja la cuenta como nueva)
-- ---------------------------------------------------------------------
create or replace function public.admin_reset_account(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_tx integer;
begin
  select count(*) into v_tx from public.transactions where user_id = p_user_id;
  delete from public.habit_coupon_grants where user_id = p_user_id;
  delete from public.reward_unlock_notifications where user_id = p_user_id;
  delete from public.bonus_recipients where user_id = p_user_id;
  delete from public.reward_redemptions where user_id = p_user_id;
  delete from public.points_ledger where user_id = p_user_id;
  delete from public.savings_contributions where user_id = p_user_id;
  delete from public.dgi_receipt_items where user_id = p_user_id;
  delete from public.dgi_receipts where user_id = p_user_id;
  delete from public.ai_insights where user_id = p_user_id;
  delete from public.transactions where user_id = p_user_id;
  delete from public.recurring_transactions where user_id = p_user_id;
  delete from public.bills where user_id = p_user_id;
  delete from public.budgets where user_id = p_user_id;
  delete from public.debts where user_id = p_user_id;
  delete from public.savings_goals where user_id = p_user_id;
  delete from public.accounts where user_id = p_user_id;
  delete from public.user_categories where user_id = p_user_id;
  delete from public.edge_function_rate_limits where user_id = p_user_id;
  update public.profiles set onboarding_completed_at = null where id = p_user_id;
  return jsonb_build_object('transactions_deleted', v_tx);
end $$;
revoke all on function public.admin_reset_account(uuid) from public, anon, authenticated;
