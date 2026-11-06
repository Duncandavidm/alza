-- Estudio de mercado para el panel (y para compartir con los aliados).
--
-- Todo es AGREGADO y ANONIMO: ninguna salida trae user_id, nombres ni
-- montos de una persona. Ademas, cada grupo (un producto, un comercio,
-- una franja de edad...) solo se muestra si lo forman al menos
-- `p_min_users` personas distintas (k-anonimato, 5 por defecto), para que
-- nadie pueda deducir la compra de un cliente en particular.
--
-- p_days: ventana de tiempo (30, 90, 365...).
-- p_ruc: si viene, el estudio se limita a los clientes de ESE comercio
--        (lo que se le puede compartir a un aliado sobre su propia
--        clientela). Sin p_ruc, es el panorama general.
--
-- Solo la service role (el panel) puede ejecutarla.

create or replace function public.market_insights(
  p_days integer default 90,
  p_ruc text default null,
  p_min_users integer default 5
) returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
with
params as (
  select now() - make_interval(days => greatest(p_days, 1)) as since,
         greatest(p_min_users, 2) as k
),
-- Facturas DGI confirmadas en la ventana (filtradas por comercio si aplica)
receipts as (
  select r.id, r.user_id, r.ruc, r.merchant_name, r.confirmed_amount as amount,
         r.payment_method,
         coalesce(r.authorized_at, r.scanned_at) at time zone 'America/Panama' as local_at
  from dgi_receipts r, params
  where r.status = 'confirmada'
    and r.confirmed_amount is not null
    and coalesce(r.authorized_at, r.scanned_at) >= params.since
    and (p_ruc is null or r.ruc = p_ruc)
),
-- Universo de personas del estudio: todos los usuarios con actividad, o
-- solo los clientes del comercio.
people as (
  select distinct t.user_id
  from transactions t, params
  where p_ruc is null and t.occurred_at >= params.since
  union
  select distinct user_id from receipts where p_ruc is not null
),
expenses as (
  select t.user_id, abs(t.amount) as amount, coalesce(nullif(trim(t.category), ''), 'Sin categoría') as category,
         t.created_at at time zone 'America/Panama' as logged_at,
         t.occurred_at
  from transactions t
  join people p on p.user_id = t.user_id, params
  where t.movement_type in ('gasto', 'pago_proveedor')
    and t.occurred_at >= params.since
),
demo as (
  select p.user_id,
         coalesce(pr.gender, 'sin_dato') as gender,
         case
           when pr.age is null then 'Sin dato'
           when pr.age < 25 then '18-24'
           when pr.age < 35 then '25-34'
           when pr.age < 45 then '35-44'
           when pr.age < 55 then '45-54'
           else '55+'
         end as age_range
  from people p
  left join profiles pr on pr.id = p.user_id
),
spend_per_user as (
  select user_id, sum(amount) as total from expenses group by user_id
)
select jsonb_build_object(
  'generated_at', now(),
  'days', p_days,
  'ruc', p_ruc,
  'min_users', (select k from params),

  'summary', jsonb_build_object(
    'people', (select count(*) from people),
    'receipts', (select count(*) from receipts),
    'receipts_total', (select coalesce(round(sum(amount), 2), 0) from receipts),
    'avg_ticket', (select round(avg(amount), 2) from receipts),
    'median_ticket', (select round(percentile_cont(0.5) within group (order by amount)::numeric, 2) from receipts),
    'expenses_total', (select coalesce(round(sum(amount), 2), 0) from expenses),
    'avg_spend_per_person_month', (
      select round(avg(total) / greatest(p_days / 30.0, 1), 2) from spend_per_user
    ),
    'receipts_per_person_month', (
      select round(count(*)::numeric / nullif(count(distinct user_id), 0) / greatest(p_days / 30.0, 1), 2)
      from receipts
    ),
    'points_issued', (
      select coalesce(sum(points), 0) from points_ledger l, params
      where l.points > 0 and l.status = 'confirmado' and l.source in ('factura', 'tarjeta')
        and l.occurred_at >= params.since and p_ruc is null
    ),
    'redemptions', (
      select count(*) from reward_redemptions rr, params
      where rr.created_at >= params.since and rr.status in ('emitido', 'entregado') and p_ruc is null
    )
  ),

  -- Medios de pago (segun la propia factura DGI)
  'payment_methods', coalesce((
    select jsonb_agg(row_to_json(x) order by x.receipts desc)
    from (
      select method, count(*) as receipts, count(distinct user_id) as people,
             round(100.0 * count(*) / nullif((select count(*) from receipts where payment_method is not null), 0), 1) as share
      from (
        select r.user_id,
               case
                 when m ilike '%crédito%' or m ilike '%credito%' then 'Tarjeta de crédito'
                 when m ilike '%débito%' or m ilike '%debito%' then 'Tarjeta de débito'
                 when m ilike '%tarjeta%' then 'Tarjeta'
                 when m ilike '%efectivo%' then 'Efectivo'
                 when m ilike '%ach%' or m ilike '%transfer%' then 'Transferencia / ACH'
                 when m ilike '%yappy%' or m ilike '%nequi%' or m ilike '%billetera%' then 'Billetera digital'
                 else initcap(trim(m))
               end as method
        from receipts r, unnest(string_to_array(r.payment_method, ',')) as m
        where r.payment_method is not null
      ) pm
      group by method
      having count(distinct user_id) >= (select k from params)
    ) x
  ), '[]'::jsonb),

  -- Genero y edad: personas, gasto promedio y ticket promedio
  'gender', coalesce((
    select jsonb_agg(row_to_json(x) order by x.people desc)
    from (
      select d.gender, count(*) as people,
             round(avg(s.total), 2) as avg_spend,
             round((select avg(r.amount) from receipts r join demo d2 on d2.user_id = r.user_id where d2.gender = d.gender), 2) as avg_ticket
      from demo d
      left join spend_per_user s on s.user_id = d.user_id
      group by d.gender
      having count(*) >= (select k from params)
    ) x
  ), '[]'::jsonb),

  'age_ranges', coalesce((
    select jsonb_agg(row_to_json(x) order by x.age_range)
    from (
      select d.age_range, count(*) as people,
             round(avg(s.total), 2) as avg_spend,
             round((select avg(r.amount) from receipts r join demo d2 on d2.user_id = r.user_id where d2.age_range = d.age_range), 2) as avg_ticket
      from demo d
      left join spend_per_user s on s.user_id = d.user_id
      group by d.age_range
      having count(*) >= (select k from params)
    ) x
  ), '[]'::jsonb),

  -- En que gastan (con p_ruc: en que MAS gastan los clientes de ese comercio)
  'categories', coalesce((
    select jsonb_agg(row_to_json(x) order by x.total desc)
    from (
      select category, round(sum(amount), 2) as total, count(*) as purchases,
             count(distinct user_id) as people,
             round(sum(amount) / count(distinct user_id), 2) as avg_per_person,
             round(100.0 * sum(amount) / nullif((select sum(amount) from expenses), 0), 1) as share
      from expenses
      group by category
      having count(distinct user_id) >= (select k from params)
    ) x
  ), '[]'::jsonb),

  -- Productos mas comprados (detalle de las facturas DGI)
  'top_products', coalesce((
    select jsonb_agg(row_to_json(x) order by x.people desc, x.times desc)
    from (
      select initcap(lower(trim(i.description))) as product,
             count(*) as times,
             round(sum(coalesce(i.quantity, 1)), 0) as units,
             round(sum(i.total), 2) as total,
             round(avg(i.unit_price), 2) as avg_price,
             count(distinct i.user_id) as people
      from dgi_receipt_items i
      join receipts r on r.id = i.receipt_id
      group by lower(trim(i.description))
      having count(distinct i.user_id) >= (select k from params)
      order by count(distinct i.user_id) desc, count(*) desc
      limit 30
    ) x
  ), '[]'::jsonb),

  -- Comercios donde mas gastan (solo en el panorama general)
  'top_merchants', coalesce((
    select jsonb_agg(row_to_json(x) order by x.total desc)
    from (
      select r.ruc,
             coalesce(max(pm.name), max(r.merchant_name), 'RUC ' || r.ruc) as merchant,
             bool_or(pm.id is not null) as is_partner,
             count(*) as visits, count(distinct r.user_id) as people,
             round(sum(r.amount), 2) as total, round(avg(r.amount), 2) as avg_ticket
      from receipts r
      left join partner_merchants pm on pm.ruc = r.ruc
      where p_ruc is null
      group by r.ruc
      having count(distinct r.user_id) >= (select k from params)
      order by sum(r.amount) desc
      limit 30
    ) x
  ), '[]'::jsonb),

  -- Horas y dias de compra (hora real de la factura DGI, hora de Panama)
  'hours', coalesce((
    select jsonb_agg(row_to_json(x) order by x.hour)
    from (
      select extract(hour from local_at)::int as hour, count(*) as receipts,
             round(avg(amount), 2) as avg_ticket
      from receipts group by 1
    ) x
  ), '[]'::jsonb),

  'weekdays', coalesce((
    select jsonb_agg(row_to_json(x) order by x.dow)
    from (
      select extract(isodow from local_at)::int as dow, count(*) as receipts,
             round(sum(amount), 2) as total, round(avg(amount), 2) as avg_ticket
      from receipts group by 1
    ) x
  ), '[]'::jsonb),

  -- Mapa de calor dia x hora (solo celdas con datos)
  'heatmap', coalesce((
    select jsonb_agg(row_to_json(x))
    from (
      select extract(isodow from local_at)::int as dow, extract(hour from local_at)::int as hour, count(*) as receipts
      from receipts group by 1, 2
    ) x
  ), '[]'::jsonb),

  -- Rango de ticket: cuantas compras caen en cada franja
  'ticket_ranges', coalesce((
    select jsonb_agg(row_to_json(x) order by x.sort)
    from (
      select case
               when amount < 5 then 1 when amount < 10 then 2 when amount < 25 then 3
               when amount < 50 then 4 when amount < 100 then 5 else 6 end as sort,
             case
               when amount < 5 then 'Menos de $5' when amount < 10 then '$5 – $10'
               when amount < 25 then '$10 – $25' when amount < 50 then '$25 – $50'
               when amount < 100 then '$50 – $100' else '$100 o más' end as range,
             count(*) as receipts
      from receipts group by 1, 2
    ) x
  ), '[]'::jsonb),

  -- Tendencia mensual
  'monthly', coalesce((
    select jsonb_agg(row_to_json(x) order by x.month)
    from (
      select to_char(date_trunc('month', local_at), 'YYYY-MM') as month,
             count(*) as receipts, count(distinct user_id) as people,
             round(sum(amount), 2) as total, round(avg(amount), 2) as avg_ticket
      from receipts group by 1
    ) x
  ), '[]'::jsonb),

  -- Recompra: de los clientes, cuantos volvieron (con p_ruc es fidelidad
  -- al comercio; sin p_ruc, frecuencia general de compra registrada).
  'loyalty', (
    select jsonb_build_object(
      'customers', count(*),
      'returning', count(*) filter (where visits > 1),
      'returning_share', round(100.0 * count(*) filter (where visits > 1) / nullif(count(*), 0), 1),
      'avg_visits', round(avg(visits), 2)
    )
    from (select user_id, count(*) as visits from receipts group by user_id) v
  ),

  -- Canjes mas populares
  'top_rewards', coalesce((
    select jsonb_agg(row_to_json(x) order by x.redemptions desc)
    from (
      select ri.name as reward, pm.name as merchant, count(*) as redemptions,
             count(*) filter (where rr.status = 'entregado') as delivered
      from reward_redemptions rr
      join reward_items ri on ri.id = rr.reward_item_id
      join partner_merchants pm on pm.id = rr.merchant_id, params
      where rr.created_at >= params.since
        and (p_ruc is null or pm.ruc = p_ruc)
      group by ri.name, pm.name
      order by count(*) desc
      limit 15
    ) x
  ), '[]'::jsonb)
);
$$;

revoke execute on function public.market_insights(integer, text, integer) from public, anon, authenticated;
grant execute on function public.market_insights(integer, text, integer) to service_role;
