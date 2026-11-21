-- 0077: estadisticas del dashboard del panel en una sola llamada.
-- Periodos en hora de Panama. Solo service_role (el panel).

create or replace function public.admin_dashboard_stats()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
with
now_pa as (select (now() at time zone 'America/Panama')::date as today),
days as (
  select generate_series((select today from now_pa) - 29, (select today from now_pa), interval '1 day')::date as d
),
weeks as (
  select generate_series(date_trunc('week', (select today from now_pa)::timestamp) - interval '11 weeks',
                         date_trunc('week', (select today from now_pa)::timestamp), interval '1 week')::date as w
),
users as (
  select id, (created_at at time zone 'America/Panama')::date as d from auth.users
),
activity as (
  select user_id, (created_at at time zone 'America/Panama')::date as d
  from public.transactions where created_at >= now() - interval '60 days'
),
receipts as (
  select user_id, status, (scanned_at at time zone 'America/Panama')::date as d from public.dgi_receipts
),
redeemed as (
  select user_id, source, merchant_id, points_cost, (delivered_at at time zone 'America/Panama')::date as d
  from public.reward_redemptions where status = 'entregado'
),
ledger as (
  select source, points, (created_at at time zone 'America/Panama')::date as d
  from public.points_ledger where status = 'confirmado' and created_at >= now() - interval '60 days'
)
select jsonb_build_object(
  'users_total', (select count(*) from users),
  'users_new_7', (select count(*) from users where d > (select today from now_pa) - 7),
  'users_new_prev_7', (select count(*) from users where d <= (select today from now_pa) - 7 and d > (select today from now_pa) - 14),
  'users_new_30', (select count(*) from users where d > (select today from now_pa) - 30),
  'users_new_prev_30', (select count(*) from users where d <= (select today from now_pa) - 30 and d > (select today from now_pa) - 60),
  'active_1', (select count(distinct user_id) from activity where d = (select today from now_pa)),
  'active_7', (select count(distinct user_id) from activity where d > (select today from now_pa) - 7),
  'active_30', (select count(distinct user_id) from activity where d > (select today from now_pa) - 30),
  'active_prev_30', (select count(distinct user_id) from activity where d <= (select today from now_pa) - 30),
  'pro_active', (select count(*) from public.subscriptions where status = 'active' and (expires_at is null or expires_at > now())),
  'receipts_total', (select count(*) from receipts where status = 'confirmada'),
  'receipts_30', (select count(*) from receipts where d > (select today from now_pa) - 30),
  'receipts_prev_30', (select count(*) from receipts where d <= (select today from now_pa) - 30 and d > (select today from now_pa) - 60),
  'receipts_pending', (select count(*) from receipts where status = 'pendiente'),
  'cashback_earned_30', (select coalesce(sum(points), 0) from ledger
                          where points > 0 and source in ('factura', 'tarjeta', 'marca', 'bono', 'referido') and d > (select today from now_pa) - 30),
  'cashback_earned_prev_30', (select coalesce(sum(points), 0) from ledger
                          where points > 0 and source in ('factura', 'tarjeta', 'marca', 'bono', 'referido') and d <= (select today from now_pa) - 30),
  'cashback_spent_30', (select coalesce(-sum(points), 0) from ledger where points < 0 and source = 'canje' and d > (select today from now_pa) - 30),
  'redemptions_30', (select count(*) from redeemed where source = 'canje' and d > (select today from now_pa) - 30),
  'benefits_30', (select count(*) from redeemed where source = 'beneficio' and d > (select today from now_pa) - 30),
  'coupons_used_30', (select count(*) from redeemed where source = 'regalo' and d > (select today from now_pa) - 30),
  'coupons_issued_30', (select count(*) from public.reward_redemptions where source = 'regalo' and created_at >= now() - interval '30 days'),
  'uses_prev_30', (select count(*) from redeemed where d <= (select today from now_pa) - 30 and d > (select today from now_pa) - 60),
  'merchants_active', (select count(*) from public.partner_merchants where status = 'active'),
  'merchants_hidden', (select count(*) from public.partner_merchants where status <> 'active'),
  'applications_new', (select count(*) from public.merchant_applications where status = 'nueva'),
  'referrals_30', (select count(*) from public.referrals where created_at >= now() - interval '30 days'),
  'ai_cost_30', (select coalesce(round(sum(cost_usd)::numeric, 2), 0) from public.ai_usage where created_at >= now() - interval '30 days'),
  'push_devices', (select count(distinct user_id) from public.device_push_tokens),
  'series_signups', (select coalesce(jsonb_agg(jsonb_build_object('d', days.d, 'v', (select count(*) from users u where u.d = days.d)) order by days.d), '[]') from days),
  'series_active', (select coalesce(jsonb_agg(jsonb_build_object('d', days.d, 'v', (select count(distinct a.user_id) from activity a where a.d = days.d)) order by days.d), '[]') from days),
  'series_receipts', (select coalesce(jsonb_agg(jsonb_build_object('d', days.d, 'v', (select count(*) from receipts r where r.d = days.d)) order by days.d), '[]') from days),
  'series_uses_weekly', (select coalesce(jsonb_agg(jsonb_build_object('d', weeks.w, 'v', (select count(*) from redeemed x where x.d >= weeks.w and x.d < weeks.w + 7)) order by weeks.w), '[]') from weeks),
  'funnel', jsonb_build_object(
    'registered', (select count(*) from users),
    'logged', (select count(distinct user_id) from public.transactions),
    'scanned', (select count(distinct user_id) from receipts where status = 'confirmada'),
    'redeemed', (select count(distinct user_id) from redeemed)
  ),
  'top_merchants', (select coalesce(jsonb_agg(t order by t.uses desc), '[]') from (
      select pm.name, count(*) as uses
      from redeemed x join public.partner_merchants pm on pm.id = x.merchant_id
      where x.d > (select today from now_pa) - 30
      group by pm.name order by count(*) desc limit 5) t)
);
$function$;
revoke all on function public.admin_dashboard_stats() from public, anon, authenticated;
grant execute on function public.admin_dashboard_stats() to service_role;
