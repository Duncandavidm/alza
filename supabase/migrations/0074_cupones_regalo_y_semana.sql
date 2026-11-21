-- 0074: "Cupones" unifica las dos formas de dar un cupon:
--   * automatico por buenos habitos (habit_coupon_rules), con la regla
--     nueva 'semana_completa' (anoto todos los dias de la semana pasada),
--     como la de puntos por semana que existia antes;
--   * regalado a quien tu quieras (bonus_grants kind 'cupon'): a clientes
--     especificos por correo, o a un grupo (ej. quienes cumplieron una
--     meta de ahorro), con un maximo de cupones a entregar (los que le
--     compraste al comercio).

-- Segmento: 'emails' (clientes especificos; no depende de filtros ni del
-- consentimiento de ofertas: es un regalo dirigido) y 'goal_met'.
create or replace function public.segment_user_ids(p_segment jsonb default '{}'::jsonb)
 returns table(user_id uuid)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
with
s as (
  select
    nullif(p_segment->>'gender', '') as gender,
    nullif(p_segment->>'age_range', '') as age_range,
    greatest(coalesce((p_segment->>'days')::int, 30), 1) as days,
    nullif(p_segment->>'activity', '') as activity,
    coalesce((p_segment->>'min_receipts')::int, 0) as min_receipts,
    nullif(translate(lower(trim(coalesce(p_segment->>'bought_product', ''))), 'áéíóúü', 'aeiouu'), '') as product,
    nullif(p_segment->>'merchant_ruc', '') as ruc,
    nullif(p_segment->>'payment', '') as payment,
    coalesce((p_segment->>'min_cashback')::int, 0) as min_cashback,
    coalesce((p_segment->>'min_savings')::numeric, 0) as min_savings,
    coalesce((p_segment->>'min_income')::numeric, 0) as min_income,
    nullif(p_segment->>'max_income', '')::numeric as max_income,
    coalesce((p_segment->>'goal_met')::boolean, false) as goal_met,
    coalesce(jsonb_typeof(p_segment->'emails') = 'array' and jsonb_array_length(p_segment->'emails') > 0, false) as by_email
),
consented as (
  select c.user_id from current_consents c where c.purpose = 'ofertas' and c.granted
),
activity as (
  select c.user_id,
         (select count(distinct (t.created_at at time zone 'America/Panama')::date)
            from transactions t, s where t.user_id = c.user_id and t.created_at >= now() - make_interval(days => s.days)) as logged_days,
         (select max(t.created_at) from transactions t where t.user_id = c.user_id) as last_activity,
         (select count(*) from dgi_receipts r, s where r.user_id = c.user_id and r.status = 'confirmada'
            and r.scanned_at >= now() - make_interval(days => s.days)) as receipts,
         (select coalesce(sum(g.current_amount), 0) from savings_goals g where g.user_id = c.user_id) as savings,
         (select coalesce(sum(t.amount), 0) / greatest(max(s.days) / 30.0, 1)
            from transactions t, s where t.user_id = c.user_id and t.movement_type = 'ingreso'
              and t.occurred_at >= now() - make_interval(days => s.days)) as monthly_income
  from consented c
),
ranked as (
  select a.*,
         percent_rank() over (order by a.logged_days) as activity_rank,
         percent_rank() over (order by a.receipts) as receipts_rank,
         percent_rank() over (order by a.savings) as savings_rank,
         percent_rank() over (order by a.monthly_income) as income_rank
  from activity a
)
select r.user_id
from ranked r
cross join s
left join profiles p on p.id = r.user_id
where not s.by_email
  and (s.gender is null or p.gender = s.gender)
  and (s.age_range is null or age_bucket(p.age) = s.age_range)
  and (s.activity is null
       or (s.activity = 'mas_activos' and r.logged_days > 0 and r.activity_rank >= 0.8)
       or (s.activity = 'menos_activos' and r.logged_days between 1 and 5)
       or (s.activity = 'inactivos' and r.last_activity is not null and r.last_activity < now() - interval '14 days')
       or (s.activity = 'top_facturas' and r.receipts > 0 and r.receipts_rank >= 0.8)
       or (s.activity = 'mas_ahorro' and r.savings > 0 and r.savings_rank >= 0.8)
       or (s.activity = 'mas_ingresos' and r.monthly_income > 0 and r.income_rank >= 0.8))
  and r.savings >= s.min_savings
  and r.monthly_income >= s.min_income
  and (s.max_income is null or r.monthly_income <= s.max_income)
  and r.receipts >= s.min_receipts
  and (not s.goal_met or exists (
        select 1 from savings_goals g
        where g.user_id = r.user_id and g.target_amount > 0 and g.current_amount >= g.target_amount
          and g.updated_at >= now() - make_interval(days => s.days)))
  and (s.product is null or exists (
        select 1 from dgi_receipt_items i join dgi_receipts d on d.id = i.receipt_id
        where d.user_id = r.user_id and d.status = 'confirmada'
          and d.scanned_at >= now() - make_interval(days => s.days)
          and translate(lower(i.description), 'áéíóúü', 'aeiouu') like '%' || s.product || '%'))
  and (s.ruc is null or exists (
        select 1 from dgi_receipts d where d.user_id = r.user_id and d.ruc = s.ruc and d.status = 'confirmada'
          and d.scanned_at >= now() - make_interval(days => s.days)))
  and (s.payment is null or exists (
        select 1 from dgi_receipts d where d.user_id = r.user_id and d.status = 'confirmada'
          and d.scanned_at >= now() - make_interval(days => s.days)
          and d.payment_method ilike any (case s.payment
                when 'tarjeta' then array['%tarjeta%', '%crédito%', '%credito%', '%débito%', '%debito%']
                when 'credito' then array['%tarjeta%crédito%', '%tarjeta%credito%', '%tarjeta de cr%']
                when 'debito' then array['%débito%', '%debito%', '%clave%']
                when 'efectivo' then array['%efectivo%']
                when 'transferencia' then array['%transfer%', '%ach%', '%dep_sito%']
                when 'yappy' then array['%yappy%']
                when 'billetera' then array['%yappy%', '%nequi%', '%billetera%', '%wallet%']
                when 'cheque' then array['%cheque%']
                when 'vale' then array['%vale%', '%regalo%', '%fidelizaci%']
                when 'otro' then array['%otro%']
                else array[s.payment] end)))
  and (s.min_cashback <= 0 or coalesce((select b.confirmed_points from points_balances b where b.user_id = r.user_id), 0) >= s.min_cashback)
union
select u.id
from auth.users u, s
where s.by_email
  and lower(u.email) in (select lower(trim(e)) from jsonb_array_elements_text(p_segment->'emails') e)
  and (u.banned_until is null or u.banned_until < now());
$function$;

-- Maximo de cupones a entregar en un regalo (los que compraste).
alter table public.bonus_grants
  add column if not exists max_recipients integer check (max_recipients is null or max_recipients > 0);

create or replace function public.grant_bonus(p_bonus_id uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_bonus public.bonus_grants;
  v_item public.reward_items;
  v_currency text;
  v_user uuid;
  v_redemption uuid;
  v_count integer := 0;
begin
  select * into v_bonus from public.bonus_grants where id = p_bonus_id for update;
  if v_bonus.id is null then raise exception 'Bono no encontrado'; end if;

  if v_bonus.kind = 'cupon' then
    select * into v_item from public.reward_items where id = v_bonus.reward_item_id;
    select reward_currency into v_currency from public.partner_merchants where id = v_item.merchant_id;
  end if;

  -- En orden aleatorio: si hay tope, nadie tiene ventaja por estar primero.
  for v_user in select s.user_id from public.segment_user_ids(v_bonus.segment) s order by random() loop
    exit when v_bonus.max_recipients is not null and v_bonus.granted_count + v_count >= v_bonus.max_recipients;

    insert into public.bonus_recipients (bonus_id, user_id) values (v_bonus.id, v_user)
      on conflict do nothing;
    continue when not found;

    if v_bonus.kind = 'cashback' then
      insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
      values (v_user, 'bono', 'bono:' || v_bonus.id || ':' || v_user, v_bonus.amount, 'confirmado',
              jsonb_build_object('bonus', v_bonus.id, 'name', v_bonus.name))
      on conflict (source, external_ref) do nothing;
    elsif v_bonus.kind = 'puntos' then
      insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
      values (v_user, 'bono_puntos', 'bono:' || v_bonus.id || ':' || v_user, v_bonus.amount, 'confirmado',
              jsonb_build_object('bonus', v_bonus.id, 'name', v_bonus.name))
      on conflict (source, external_ref) do nothing;
    else
      insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, status,
          expires_at, currency, source, bonus_id, gift_message)
      values (v_user, v_item.id, v_item.merchant_id, v_item.points_cost, public.new_redemption_code(), 'emitido',
          now() + make_interval(days => v_bonus.expires_days), coalesce(v_currency, 'cashback'), 'regalo', v_bonus.id,
          v_bonus.message)
      returning id into v_redemption;
      update public.bonus_recipients set redemption_id = v_redemption where bonus_id = v_bonus.id and user_id = v_user;
    end if;
    v_count := v_count + 1;
  end loop;

  update public.bonus_grants
     set status = 'granted', granted_at = coalesce(granted_at, now()), granted_count = granted_count + v_count
   where id = v_bonus.id;
  return v_count;
end $function$;

-- Regla semanal: anoto sus movimientos los 7 dias de la semana pasada.
alter table public.habit_coupon_rules drop constraint if exists habit_coupon_rules_rule_type_check;
alter table public.habit_coupon_rules add constraint habit_coupon_rules_rule_type_check
  check (rule_type = any (array['ahorro_ingresos', 'meta_a_tiempo', 'presupuestos', 'dias_registrados',
                                'salud_financiera', 'semana_completa', 'todos']));

create or replace function public.habit_rule_reason(p_rule habit_coupon_rules)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select case p_rule.rule_type
    when 'ahorro_ingresos' then 'por ahorrar el ' || rtrim(to_char(p_rule.threshold, 'FM999990.##'), '.') || '% de tus ingresos en el mes'
    when 'meta_a_tiempo' then 'por cumplir una meta de ahorro a tiempo'
    when 'presupuestos' then 'por cumplir todos tus presupuestos del mes'
    when 'dias_registrados' then 'por anotar tus movimientos ' || trim(to_char(p_rule.threshold, 'FM990')) || ' días del mes'
    when 'semana_completa' then 'por anotar tus movimientos todos los días de la semana'
    when 'todos' then 'por ser de MonAvi'
    else 'por tener una salud financiera de ' || trim(to_char(p_rule.threshold, 'FM990')) || '/100 o más'
  end;
$function$;

create or replace function public.issue_habit_coupons()
 returns table(user_id uuid, redemption_id uuid, rule_name text, coupon_name text, merchant text, reason text, expires_at timestamp with time zone, image_url text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_rule public.habit_coupon_rules;
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_month date := ((now() at time zone 'America/Panama') - interval '1 month')::date;
  v_period text := to_char(((now() at time zone 'America/Panama') - interval '1 month'), 'YYYY-MM');
  -- Semana pasada (lunes a domingo, hora de Panama).
  v_week_start date := date_trunc('week', (now() at time zone 'America/Panama') - interval '7 days')::date;
  v_week text := to_char(date_trunc('week', (now() at time zone 'America/Panama') - interval '7 days'), 'IYYY-"S"IW');
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
             case when v_rule.rule_type = 'meta_a_tiempo' then g.id::text
                  when v_rule.rule_type = 'todos' then 'todos'
                  when v_rule.rule_type = 'semana_completa' then v_week
                  else v_period end as period_key,
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

      if v_rule.rule_type = 'semana_completa' then
        v_ok := (select count(distinct (t.created_at at time zone 'America/Panama')::date)
                   from public.transactions t
                  where t.user_id = v_candidate.uid
                    and (t.created_at at time zone 'America/Panama')::date between v_week_start and v_week_start + 6) >= 7;
      else
        v_metrics := case when v_rule.rule_type = 'todos' then '{}'::jsonb
                          else public.financial_month_metrics(v_candidate.uid, v_month) end;
        v_ok := v_rule.rule_type = 'todos' or (v_metrics->>'logged_days')::int >= v_rule.min_logged_days and case v_rule.rule_type
          when 'ahorro_ingresos' then (v_metrics->>'income')::numeric > 0
                                   and coalesce((v_metrics->>'savings_rate')::numeric, 0) >= v_rule.threshold
          when 'presupuestos' then (v_metrics->>'budgets')::int >= greatest(v_rule.threshold, 1)
                                and (v_metrics->>'budgets_met')::int = (v_metrics->>'budgets')::int
          when 'dias_registrados' then (v_metrics->>'logged_days')::int >= v_rule.threshold
          when 'salud_financiera' then (v_metrics->>'score')::numeric >= v_rule.threshold
          when 'meta_a_tiempo' then true
          else false end;
        if v_rule.rule_type = 'meta_a_tiempo' then
          v_ok := (public.financial_month_metrics(v_candidate.uid, (now() at time zone 'America/Panama')::date)->>'logged_days')::int
                  >= least(v_rule.min_logged_days, extract(day from (now() at time zone 'America/Panama'))::int);
        end if;
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
end $function$;
