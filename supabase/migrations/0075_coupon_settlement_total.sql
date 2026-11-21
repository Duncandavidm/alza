-- 0075: la liquidacion a comercios suma TODOS los cupones que paga MonAvi:
-- los automaticos por buenos habitos (habit_coupon_grants) y los regalados
-- desde el panel (bonus_grants). Ambos se emiten como reward_redemptions
-- con source = 'regalo'.

create or replace function public.coupon_settlement(p_months integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with coupons as (
    select rr.id, rr.merchant_id, rr.points_cost, rr.status, rr.expires_at, rr.delivered_at,
           exists (select 1 from public.habit_coupon_grants g where g.redemption_id = rr.id) as by_habit
    from public.reward_redemptions rr
    where rr.source = 'regalo'
  ),
  pending as (
    select merchant_id, count(*) as outstanding, round(sum(points_cost) / 100.0, 2) as outstanding_usd
    from coupons
    where status = 'emitido' and expires_at >= now()
    group by merchant_id
  )
  select coalesce(jsonb_agg(row_to_json(x) order by x.month desc, x.merchant), '[]'::jsonb)
  from (
    select to_char(date_trunc('month', c.delivered_at at time zone 'America/Panama'), 'YYYY-MM') as month,
           pm.id as merchant_id, pm.name as merchant,
           count(*) filter (where c.by_habit) as delivered_habits,
           count(*) filter (where not c.by_habit) as delivered_gifts,
           count(*) as delivered,
           round(sum(c.points_cost) / 100.0, 2) as amount_usd,
           coalesce(max(p.outstanding), 0) as outstanding,
           coalesce(max(p.outstanding_usd), 0) as outstanding_usd
    from coupons c
    join public.partner_merchants pm on pm.id = c.merchant_id
    left join pending p on p.merchant_id = pm.id
    where c.status = 'entregado'
      and c.delivered_at >= date_trunc('month', now()) - make_interval(months => greatest(p_months, 1))
    group by 1, pm.id, pm.name
  ) x;
$function$;

-- El nombre viejo sigue funcionando (mismo resultado, con mas columnas).
create or replace function public.habit_coupon_settlement(p_months integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select public.coupon_settlement(p_months);
$function$;

revoke all on function public.coupon_settlement(integer) from public, anon, authenticated;
