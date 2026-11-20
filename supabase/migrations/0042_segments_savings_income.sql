-- Segmentos por ahorro e ingresos:
--   activity      + mas_ahorro (20% que mas ha ahorrado en metas)
--                 + mas_ingresos (20% con mas ingreso mensual registrado)
--   min_savings   ahorro minimo en metas (US$)
--   min_income    ingreso mensual promedio minimo (US$, en la ventana `days`)
--   max_income    ingreso mensual promedio maximo (US$)
--   payment       tarjeta | credito | debito | efectivo | transferencia | yappy |
--                 billetera | cheque | vale | otro (segun la forma de pago de la
--                 factura; la marca de la tarjeta NO viene en la factura)
create or replace function public.segment_user_ids(p_segment jsonb default '{}'::jsonb)
returns table (user_id uuid)
language sql stable security definer set search_path = public, pg_temp as $$
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
    nullif(p_segment->>'max_income', '')::numeric as max_income
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
         -- Ingreso mensual promedio en la ventana (minimo un mes)
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
where (s.gender is null or p.gender = s.gender)
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
  and (s.min_cashback <= 0 or coalesce((select b.confirmed_points from points_balances b where b.user_id = r.user_id), 0) >= s.min_cashback);
$$;
revoke execute on function public.segment_user_ids(jsonb) from public, anon, authenticated;
