-- Cupones "para todos" (sin reglas): se entregan una vez a cada persona,
-- tambien a quien se registre despues, hasta el maximo de cupones.
alter table public.habit_coupon_rules drop constraint if exists habit_coupon_rules_rule_type_check;
alter table public.habit_coupon_rules add constraint habit_coupon_rules_rule_type_check check (rule_type in
  ('ahorro_ingresos', 'meta_a_tiempo', 'presupuestos', 'dias_registrados', 'salud_financiera', 'todos'));

create or replace function public.habit_rule_reason(p_rule public.habit_coupon_rules)
returns text
language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case p_rule.rule_type
    when 'ahorro_ingresos' then 'por ahorrar el ' || rtrim(to_char(p_rule.threshold, 'FM999990.##'), '.') || '% de tus ingresos en el mes'
    when 'meta_a_tiempo' then 'por cumplir una meta de ahorro a tiempo'
    when 'presupuestos' then 'por cumplir todos tus presupuestos del mes'
    when 'dias_registrados' then 'por anotar tus movimientos ' || trim(to_char(p_rule.threshold, 'FM990')) || ' días del mes'
    when 'todos' then 'por ser de MonAvi'
    else 'por tener una salud financiera de ' || trim(to_char(p_rule.threshold, 'FM990')) || ' puntos o más'
  end;
$$;

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
             case when v_rule.rule_type = 'meta_a_tiempo' then g.id::text
                  when v_rule.rule_type = 'todos' then 'todos'
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
      -- "Para todos": sin reglas, una vez por persona.
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
