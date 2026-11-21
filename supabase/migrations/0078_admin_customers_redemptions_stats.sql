-- 0078: estadisticas para las paginas Clientes y Canjes del panel.
-- Periodos en hora de Panama. Solo service_role (el panel).

create or replace function public.admin_customers_stats()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
with
now_pa as (select (now() at time zone 'America/Panama')::date as today),
days as (
  select generate_series((select today from now_pa) - 89, (select today from now_pa), interval '1 day')::date as d
),
weeks as (
  select generate_series(date_trunc('week', (select today from now_pa)::timestamp) - interval '11 weeks',
                         date_trunc('week', (select today from now_pa)::timestamp), interval '1 week')::date as w
),
users as (
  select u.id, (u.created_at at time zone 'America/Panama')::date as d, p.gender, p.age
  from auth.users u left join public.profiles p on p.id = u.id
),
activity as (
  select user_id, (created_at at time zone 'America/Panama')::date as d
  from public.transactions where created_at >= now() - interval '60 days'
),
active30 as (
  select distinct user_id from activity where d > (select today from now_pa) - 30
),
ever_logged as (select distinct user_id from public.transactions),
older as (select id from users where d <= (select today from now_pa) - 30)
select jsonb_build_object(
  'total', (select count(*) from users),
  'new_30', (select count(*) from users where d > (select today from now_pa) - 30),
  'new_prev_30', (select count(*) from users where d <= (select today from now_pa) - 30 and d > (select today from now_pa) - 60),
  'active_30', (select count(*) from active30),
  'active_prev_30', (select count(distinct user_id) from activity where d <= (select today from now_pa) - 30),
  'older_total', (select count(*) from older),
  'older_retained', (select count(*) from older o join active30 a on a.user_id = o.id),
  'push', (select count(distinct user_id) from public.device_push_tokens),
  'pro', (select count(*) from public.subscriptions where status = 'active' and (expires_at is null or expires_at > now())),
  'consent_estudio', (select count(*) from public.current_consents where purpose = 'estudio_mercado' and granted),
  'consent_ofertas', (select count(*) from public.current_consents where purpose = 'ofertas' and granted),
  'with_receipt', (select count(distinct user_id) from public.dgi_receipts where status = 'confirmada'),
  'segments', jsonb_build_object(
    'active', (select count(*) from active30),
    'dormant', (select count(*) from ever_logged e where not exists (select 1 from active30 a where a.user_id = e.user_id)),
    'never', (select count(*) from users u where not exists (select 1 from ever_logged e where e.user_id = u.id))
  ),
  'series_total', (select coalesce(jsonb_agg(jsonb_build_object('d', days.d, 'v', (select count(*) from users u where u.d <= days.d)) order by days.d), '[]') from days),
  'series_signups_weekly', (select coalesce(jsonb_agg(jsonb_build_object('d', weeks.w, 'v', (select count(*) from users u where u.d >= weeks.w and u.d < weeks.w + 7)) order by weeks.w), '[]') from weeks),
  'genders', (select coalesce(jsonb_agg(jsonb_build_object('label', g.label, 'v', g.v) order by g.v desc), '[]') from (
      select coalesce(nullif(initcap(gender), ''), 'Sin dato') as label, count(*) as v from users group by 1) g),
  'ages', (select coalesce(jsonb_agg(jsonb_build_object('label', a.label, 'v', a.v) order by a.ord), '[]') from (
      select case when age is null then 'Sin dato' when age < 25 then 'Menos de 25' when age < 35 then '25 a 34'
                  when age < 45 then '35 a 44' when age < 55 then '45 a 54' else '55 o más' end as label,
             case when age is null then 9 when age < 25 then 1 when age < 35 then 2 when age < 45 then 3
                  when age < 55 then 4 else 5 end as ord,
             count(*) as v
      from users group by 1, 2) a)
);
$function$;
revoke all on function public.admin_customers_stats() from public, anon, authenticated;
grant execute on function public.admin_customers_stats() to service_role;

create or replace function public.admin_redemptions_stats()
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
r as (
  select rr.*, (rr.delivered_at at time zone 'America/Panama')::date as dd
  from public.reward_redemptions rr
),
used as (select * from r where status = 'entregado'),
used30 as (select * from used where dd > (select today from now_pa) - 30)
select jsonb_build_object(
  'uses_30', (select count(*) from used30),
  'uses_prev_30', (select count(*) from used where dd <= (select today from now_pa) - 30 and dd > (select today from now_pa) - 60),
  'canjes_30', (select count(*) from used30 where source = 'canje'),
  'descuentos_30', (select count(*) from used30 where source = 'beneficio'),
  'cupones_30', (select count(*) from used30 where source = 'regalo'),
  'clients_30', (select count(distinct user_id) from used30),
  'cashback_spent_30', (select coalesce(sum(points_cost), 0) from used30 where source = 'canje' and coalesce(currency, 'cashback') = 'cashback'),
  'via_caja_30', (select count(*) from used30 where delivered_via = 'comercio'),
  'via_panel_30', (select count(*) from used30 where delivered_via = 'panel'),
  'pending', (select count(*) from r where status = 'emitido' and expires_at > now()),
  'overdue', (select count(*) from r where status = 'emitido' and expires_at <= now()),
  'lost_30', (select count(*) from r where status in ('vencido', 'cancelado') and created_at >= now() - interval '30 days'),
  'created_30', (select count(*) from r where created_at >= now() - interval '30 days'),
  'coupons_issued', (select count(*) from r where source = 'regalo'),
  'coupons_used', (select count(*) from used where source = 'regalo'),
  'series_daily', (select coalesce(jsonb_agg(jsonb_build_object('d', days.d, 'v', (select count(*) from used u where u.dd = days.d)) order by days.d), '[]') from days),
  'top_merchants', (select coalesce(jsonb_agg(t order by t.v desc), '[]') from (
      select pm.name as label, count(*) as v from used30 u join public.partner_merchants pm on pm.id = u.merchant_id
      group by pm.name order by count(*) desc limit 6) t),
  'top_items', (select coalesce(jsonb_agg(t order by t.v desc), '[]') from (
      select ri.name || ' · ' || pm.name as label, count(*) as v
      from used30 u join public.reward_items ri on ri.id = u.reward_item_id
      join public.partner_merchants pm on pm.id = u.merchant_id
      group by 1 order by count(*) desc limit 6) t)
);
$function$;
revoke all on function public.admin_redemptions_stats() from public, anon, authenticated;
grant execute on function public.admin_redemptions_stats() to service_role;
