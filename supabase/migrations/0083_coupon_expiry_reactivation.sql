-- 1.0.5: aviso de cupon por vencer, segmento "sin facturas" para reactivar, resumen del mes y
-- "Tus compras".

-- ---------------------------------------------------------------------
-- 1) "Tu cupón en Café La Esquina vence mañana"
-- ---------------------------------------------------------------------
alter table public.reward_redemptions add column if not exists expiry_reminder_sent_at timestamptz;

-- Cupones sin usar que vencen en las proximas 36 horas (la corrida diaria
-- de las 8:15 los avisa una sola vez). Los de vigencia muy corta (menos de
-- 3 dias) no se avisan: ya se entregaron con fecha cercana.
create or replace function public.coupons_expiring_soon()
returns table(redemption_id uuid, user_id uuid, coupon text, merchant text, expires_at timestamptz, image_url text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select rr.id, rr.user_id, ri.name, pm.name, rr.expires_at, coalesce(ri.photo_url, pm.logo_url)
  from public.reward_redemptions rr
  join public.reward_items ri on ri.id = rr.reward_item_id
  join public.partner_merchants pm on pm.id = rr.merchant_id
  where rr.status = 'emitido' and rr.expiry_reminder_sent_at is null
    and rr.expires_at > now() + interval '2 hours'
    and rr.expires_at <= now() + interval '36 hours'
    and rr.expires_at - rr.created_at >= interval '3 days';
$$;
revoke all on function public.coupons_expiring_soon() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) Segmento "sin facturas en N días" (avisos de reactivacion)
-- ---------------------------------------------------------------------
create or replace function public.segment_user_ids(p_segment jsonb DEFAULT '{}'::jsonb)
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
         (select max(r.scanned_at) from dgi_receipts r where r.user_id = c.user_id) as last_scan,
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
       or (s.activity = 'sin_facturas' and (r.last_scan is null or r.last_scan < now() - make_interval(days => s.days)))
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

-- ---------------------------------------------------------------------
-- 3) Resumen del mes de facturas (para compartir) y "Tus compras"
-- ---------------------------------------------------------------------
create or replace function public.my_invoice_month_summary(p_month date default null)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  with me as (select auth.uid() as uid),
  b as (
    select date_trunc('month', coalesce(p_month, (now() at time zone 'America/Panama')::date))::date as s,
           (date_trunc('month', coalesce(p_month, (now() at time zone 'America/Panama')::date)) + interval '1 month')::date as e
  ),
  r as (
    select d.id, coalesce(nullif(trim(d.merchant_name), ''), 'RUC ' || d.ruc) as merchant,
           coalesce(d.confirmed_amount, abs(t.amount), 0) as amount
    from public.dgi_receipts d
    left join public.transactions t on t.id = d.transaction_id
    cross join b
    where d.user_id = (select uid from me) and d.status in ('pendiente', 'confirmada')
      and (d.scanned_at at time zone 'America/Panama')::date >= b.s
      and (d.scanned_at at time zone 'America/Panama')::date < b.e
  )
  select jsonb_build_object(
    'month', to_char((select s from b), 'YYYY-MM'),
    'receipts', (select count(*) from r),
    'spent', (select coalesce(sum(amount), 0) from r),
    'cashback_cents', (select coalesce(sum(l.points), 0)
                       from public.points_ledger l, b
                       where l.user_id = (select uid from me) and l.points > 0
                         and l.source in ('factura', 'tarjeta', 'marca', 'bono') and l.status <> 'anulado'
                         and (l.occurred_at at time zone 'America/Panama')::date >= b.s
                         and (l.occurred_at at time zone 'America/Panama')::date < b.e),
    'merchant_count', (select count(distinct merchant) from r),
    'merchants', coalesce((select jsonb_agg(jsonb_build_object('name', x.merchant, 'receipts', x.n, 'amount', x.total)
                                            order by x.n desc, x.total desc)
                           from (select merchant, count(*) as n, sum(amount) as total
                                 from r group by merchant order by count(*) desc, sum(amount) desc limit 5) x), '[]'::jsonb)
  )
  where (select uid from me) is not null;
$$;
revoke all on function public.my_invoice_month_summary(date) from public, anon;
grant execute on function public.my_invoice_month_summary(date) to authenticated;

-- Productos de las facturas propias con su precio, para comparar donde
-- sale mas barato.
create or replace function public.my_purchases(p_days integer default 180)
returns table(description text, merchant text, quantity numeric, unit_price numeric, total numeric, bought_at timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select i.description,
         coalesce(nullif(trim(d.merchant_name), ''), 'RUC ' || d.ruc),
         i.quantity,
         coalesce(i.unit_price, case when coalesce(i.quantity, 0) > 0 then round(i.total / i.quantity, 2) end),
         i.total,
         coalesce(d.authorized_at, d.scanned_at)
  from public.dgi_receipt_items i
  join public.dgi_receipts d on d.id = i.receipt_id
  where d.user_id = auth.uid() and i.user_id = auth.uid()
    and d.status in ('pendiente', 'confirmada')
    and coalesce(d.authorized_at, d.scanned_at) >= now() - make_interval(days => least(greatest(p_days, 1), 730))
    and nullif(trim(i.description), '') is not null
  order by coalesce(d.authorized_at, d.scanned_at) desc
  limit 2000;
$$;
revoke all on function public.my_purchases(integer) from public, anon;
grant execute on function public.my_purchases(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 4) Push que abre la camara ("scan"): avisos de reactivacion
-- ---------------------------------------------------------------------
alter table public.push_campaigns drop constraint if exists push_campaigns_screen_check;
alter table public.push_campaigns add constraint push_campaigns_screen_check
  check (screen = any (array['home', 'points', 'rewards', 'redemptions', 'scan']));
