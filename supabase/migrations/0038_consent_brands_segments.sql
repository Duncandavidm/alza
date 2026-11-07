-- Estudio de mercado: consentimiento explicito, campañas de marcas y
-- segmentacion.
--
-- 1. user_consents: registro (solo se agrega, nunca se edita) de lo que
--    cada persona acepto, con version del texto y fecha. Vale la ULTIMA
--    decision por proposito. El estudio de mercado solo incluye a quien
--    acepto 'estudio_mercado' (opt-in, Ley 81 de 2019 de Panama).
-- 2. brand_campaigns: una marca paga por "si compras X ganas mas". La
--    factura DGI (detalle de productos) prueba la compra; cada venta
--    queda en campaign_conversions, que es lo que se le cobra a la marca.
-- 3. market_insights con filtros: genero, edad, medio de pago, producto
--    y categoria; mas secciones (quincena, momento del dia, frecuencia,
--    donde mas compran sus clientes, pago x genero). k-anonimato en todo
--    y, si el segmento tiene menos de k personas, no devuelve detalle.

-- ---------------------------------------------------------------- 1
create table public.user_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  purpose text not null check (purpose in ('estudio_mercado', 'programa_recompensas')),
  granted boolean not null,
  text_version integer not null default 1,
  source text not null default 'app' check (source in ('app', 'soporte')),
  decided_at timestamptz not null default now()
);
create index user_consents_user_purpose_idx on public.user_consents (user_id, purpose, decided_at desc);

alter table public.user_consents enable row level security;
create policy "consents_select_own" on public.user_consents
  for select to authenticated using (user_id = (select auth.uid()));
create policy "consents_insert_own" on public.user_consents
  for insert to authenticated with check (user_id = (select auth.uid()) and source = 'app');

-- La fecha la pone el servidor, no el telefono.
create function public.user_consents_force_now() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.decided_at := now();
  return new;
end $$;
create trigger user_consents_force_now before insert on public.user_consents
  for each row execute function public.user_consents_force_now();

-- Ultima decision por persona y proposito.
create view public.current_consents with (security_invoker = true) as
  select distinct on (user_id, purpose) user_id, purpose, granted, text_version, decided_at
  from public.user_consents
  order by user_id, purpose, decided_at desc;
grant select on public.current_consents to authenticated;

-- Personas que entran al estudio (aceptaron y no pidieron salir).
create function public.insights_consented_users() returns table (user_id uuid)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.user_id from public.current_consents c
  where c.purpose = 'estudio_mercado' and c.granted
    and not exists (select 1 from public.profiles p where p.id = c.user_id and p.exclude_from_insights);
$$;
revoke execute on function public.insights_consented_users() from public, anon, authenticated;

-- ---------------------------------------------------------------- 2
alter table public.points_ledger drop constraint points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check
  check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje', 'canje_puntos', 'marca', 'marca_puntos'));

create or replace view public.points_balances
  with (security_invoker = true)
  as
  select
    user_id,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca')), 0) as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca')), 0) as pending_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('habito', 'canje_puntos', 'marca_puntos')), 0) as habit_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source = 'habito' and points > 0), 0) as habit_points_earned
  from public.points_ledger
  group by user_id;

create table public.brand_campaigns (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  name text not null,
  description text,
  image_url text,
  sponsor_contact text,
  -- Palabras que deben aparecer en la descripcion del producto en la
  -- factura (ej. {'coca cola','coca-cola'}). Se comparan sin acentos ni
  -- mayusculas.
  keywords text[] not null check (cardinality(keywords) > 0),
  -- null = en cualquier comercio; si no, solo en estos RUC.
  merchant_rucs text[],
  bonus_currency text not null default 'puntos' check (bonus_currency in ('puntos', 'cashback')),
  -- Premio por unidad comprada (puntos, o centavos si es cashback)...
  bonus_per_unit integer check (bonus_per_unit is null or bonus_per_unit > 0),
  -- ...y/o extra por cada dolar de esas lineas (1 = 1 punto o 1 centavo
  -- por dolar; el cashback base es 1, asi que 1 = "el doble").
  bonus_percent numeric(6, 2) check (bonus_percent is null or bonus_percent > 0),
  max_units_per_receipt integer not null default 5 check (max_units_per_receipt > 0),
  -- Lo que la marca le paga a MonAvi por cada venta verificada.
  fee_per_conversion_cents integer check (fee_per_conversion_cents is null or fee_per_conversion_cents >= 0),
  -- Tope de premios a repartir (en la moneda del bono).
  budget_total integer check (budget_total is null or budget_total > 0),
  budget_spent integer not null default 0,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft', 'active', 'paused', 'ended', 'budget_exhausted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (bonus_per_unit is not null or bonus_percent is not null)
);

alter table public.brand_campaigns enable row level security;
-- La app solo ve las campañas vigentes y solo las columnas publicas
-- (no el contacto, la tarifa ni el presupuesto).
create policy "brand_campaigns_select_active" on public.brand_campaigns
  for select to authenticated
  using (status = 'active' and starts_at <= now() and (ends_at is null or ends_at > now()));
revoke all on public.brand_campaigns from anon, authenticated;
grant select (id, brand, name, description, image_url, merchant_rucs, bonus_currency, bonus_per_unit,
              bonus_percent, max_units_per_receipt, starts_at, ends_at, status)
  on public.brand_campaigns to authenticated;

create table public.campaign_conversions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.brand_campaigns (id) on delete cascade,
  receipt_id uuid not null references public.dgi_receipts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  ruc text not null,
  units numeric(14, 3) not null,
  sales_amount numeric(14, 2) not null,
  bonus integer not null,
  bonus_currency text not null,
  purchased_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (campaign_id, receipt_id)
);
create index campaign_conversions_campaign_idx on public.campaign_conversions (campaign_id, purchased_at);
create index campaign_conversions_user_idx on public.campaign_conversions (user_id);
create index campaign_conversions_receipt_idx on public.campaign_conversions (receipt_id);
alter table public.campaign_conversions enable row level security;
create policy "campaign_conversions_select_own" on public.campaign_conversions
  for select to authenticated using (user_id = (select auth.uid()));

-- Aplica las campañas a UNA factura confirmada. Idempotente: una factura
-- suma una sola vez por campaña. Devuelve cuantas campañas aplicaron.
create function public.apply_brand_campaigns(p_receipt_id uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_receipt public.dgi_receipts;
  v_at timestamptz;
  v_campaign public.brand_campaigns;
  v_units numeric;
  v_sales numeric;
  v_bonus integer;
  v_conversion uuid;
  v_applied integer := 0;
begin
  select * into v_receipt from public.dgi_receipts where id = p_receipt_id and status = 'confirmada';
  if not found then return 0; end if;
  v_at := coalesce(v_receipt.authorized_at, v_receipt.scanned_at);

  for v_campaign in
    select * from public.brand_campaigns c
    where c.status = 'active' and c.starts_at <= v_at and (c.ends_at is null or c.ends_at > v_at)
      and (c.merchant_rucs is null or v_receipt.ruc = any (c.merchant_rucs))
    order by c.created_at
    for update
  loop
    select coalesce(sum(coalesce(i.quantity, 1)), 0), coalesce(sum(coalesce(i.total, 0)), 0)
      into v_units, v_sales
    from public.dgi_receipt_items i
    where i.receipt_id = p_receipt_id
      and exists (
        select 1 from unnest(v_campaign.keywords) k
        where translate(lower(i.description), 'áéíóúü', 'aeiouu')
              like '%' || translate(lower(trim(k)), 'áéíóúü', 'aeiouu') || '%'
      );
    continue when v_units <= 0;

    v_units := least(v_units, v_campaign.max_units_per_receipt);
    v_bonus := coalesce(v_campaign.bonus_per_unit * greatest(floor(v_units), 1)::integer, 0)
             + coalesce(floor(v_sales * v_campaign.bonus_percent)::integer, 0);
    continue when v_bonus <= 0;

    if v_campaign.budget_total is not null then
      if v_campaign.budget_spent >= v_campaign.budget_total then
        update public.brand_campaigns set status = 'budget_exhausted', updated_at = now() where id = v_campaign.id;
        continue;
      end if;
      v_bonus := least(v_bonus, v_campaign.budget_total - v_campaign.budget_spent);
    end if;

    v_conversion := null;
    insert into public.campaign_conversions (campaign_id, receipt_id, user_id, ruc, units, sales_amount, bonus, bonus_currency, purchased_at)
    values (v_campaign.id, p_receipt_id, v_receipt.user_id, v_receipt.ruc, v_units, round(v_sales, 2), v_bonus, v_campaign.bonus_currency, v_at)
    on conflict (campaign_id, receipt_id) do nothing
    returning id into v_conversion;
    continue when v_conversion is null;

    insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
    values (v_receipt.user_id,
            case when v_campaign.bonus_currency = 'puntos' then 'marca_puntos' else 'marca' end,
            'marca:' || v_campaign.id || ':' || p_receipt_id, v_bonus, 'confirmado', v_at,
            jsonb_build_object('campaign', v_campaign.id, 'brand', v_campaign.brand, 'units', v_units))
    on conflict (source, external_ref) do nothing;

    update public.brand_campaigns
      set budget_spent = budget_spent + v_bonus,
          status = case when budget_total is not null and budget_spent + v_bonus >= budget_total
                        then 'budget_exhausted' else status end,
          updated_at = now()
      where id = v_campaign.id;
    v_applied := v_applied + 1;
  end loop;
  return v_applied;
end $$;
revoke execute on function public.apply_brand_campaigns(uuid) from public, anon, authenticated;

-- Reporte para cobrarle a la marca: solo agregados (por comercio con al
-- menos 5 personas).
create function public.brand_campaign_report(p_campaign_id uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'conversions', count(*),
    'people', count(distinct user_id),
    'units', coalesce(round(sum(units), 0), 0),
    'sales', coalesce(round(sum(sales_amount), 2), 0),
    'bonus_given', coalesce(sum(bonus), 0),
    'amount_due_cents', count(*) * coalesce((select fee_per_conversion_cents from brand_campaigns where id = p_campaign_id), 0),
    'by_merchant', coalesce((
      select jsonb_agg(row_to_json(x) order by x.units desc) from (
        select coalesce(max(r.merchant_name), 'RUC ' || cc.ruc) as merchant, count(*) as conversions,
               count(distinct cc.user_id) as people, round(sum(cc.units), 0) as units, round(sum(cc.sales_amount), 2) as sales
        from campaign_conversions cc join dgi_receipts r on r.id = cc.receipt_id
        where cc.campaign_id = p_campaign_id
        group by cc.ruc having count(distinct cc.user_id) >= 5
      ) x), '[]'::jsonb),
    'by_week', coalesce((
      select jsonb_agg(row_to_json(x) order by x.week) from (
        select to_char(date_trunc('week', purchased_at at time zone 'America/Panama'), 'YYYY-MM-DD') as week,
               count(*) as conversions, round(sum(units), 0) as units, round(sum(sales_amount), 2) as sales
        from campaign_conversions where campaign_id = p_campaign_id group by 1
      ) x), '[]'::jsonb)
  )
  from campaign_conversions where campaign_id = p_campaign_id;
$$;
revoke execute on function public.brand_campaign_report(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3
create or replace function public.age_bucket(p_age integer) returns text
language sql immutable set search_path = public, pg_temp as $$
  select case
    when p_age is null then 'Sin dato'
    when p_age < 25 then '18-24'
    when p_age < 35 then '25-34'
    when p_age < 45 then '35-44'
    when p_age < 55 then '45-54'
    else '55+' end;
$$;

drop function if exists public.market_insights(integer, text, integer);

create function public.market_insights(
  p_days integer default 90,
  p_ruc text default null,
  p_min_users integer default 5,
  p_gender text default null,       -- femenino | masculino | otro | sin_dato
  p_age_range text default null,    -- 18-24 | 25-34 | 35-44 | 45-54 | 55+ | Sin dato
  p_payment text default null,      -- tarjeta | credito | debito | efectivo | ach | billetera
  p_product text default null,      -- texto en el detalle de la factura (ej. "coca cola")
  p_category text default null      -- categoria de gasto registrada en la app
) returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
with
params as (
  select now() - make_interval(days => greatest(p_days, 1)) as since,
         greatest(p_min_users, 2) as k,
         jsonb_strip_nulls(jsonb_build_object('gender', p_gender, 'age_range', p_age_range, 'payment', p_payment,
                                              'product', p_product, 'category', p_category)) as filters,
         case p_payment
           when 'credito' then array['%crédito%', '%credito%']
           when 'debito' then array['%débito%', '%debito%']
           when 'tarjeta' then array['%tarjeta%', '%crédito%', '%credito%', '%débito%', '%debito%']
           when 'efectivo' then array['%efectivo%']
           when 'ach' then array['%ach%', '%transfer%']
           when 'billetera' then array['%yappy%', '%nequi%', '%billetera%']
           else null end as pay_patterns,
         nullif(translate(lower(trim(coalesce(p_product, ''))), 'áéíóúü', 'aeiouu'), '') as product_q
),
-- Solo personas que aceptaron el estudio y que caen en el segmento.
consented as (
  select c.user_id
  from insights_consented_users() c
  left join profiles pr on pr.id = c.user_id
  where (p_gender is null
         or (p_gender = 'sin_dato' and (pr.gender is null or pr.gender = 'prefiero_no_decir'))
         or pr.gender = p_gender)
    and (p_age_range is null or age_bucket(pr.age) = p_age_range)
),
receipts as (
  select r.id, r.user_id, r.ruc, r.merchant_name, r.confirmed_amount as amount,
         r.payment_method,
         coalesce(r.authorized_at, r.scanned_at) at time zone 'America/Panama' as local_at
  from dgi_receipts r
  join consented c on c.user_id = r.user_id, params
  where r.status = 'confirmada'
    and r.confirmed_amount is not null
    and coalesce(r.authorized_at, r.scanned_at) >= params.since
    and (p_ruc is null or r.ruc = p_ruc)
    and (params.pay_patterns is null or r.payment_method ilike any (params.pay_patterns))
    and (params.product_q is null or exists (
          select 1 from dgi_receipt_items i
          where i.receipt_id = r.id
            and translate(lower(i.description), 'áéíóúü', 'aeiouu') like '%' || params.product_q || '%'))
),
people as (
  select distinct t.user_id
  from transactions t
  join consented c on c.user_id = t.user_id, params
  where p_ruc is null and p_payment is null and p_product is null
    and t.occurred_at >= params.since
    and (p_category is null or t.category = p_category)
  union
  select distinct user_id from receipts where p_category is null or p_ruc is not null or p_payment is not null or p_product is not null
),
expenses as (
  select t.user_id, abs(t.amount) as amount, coalesce(nullif(trim(t.category), ''), 'Sin categoría') as category,
         t.created_at at time zone 'America/Panama' as logged_at,
         t.occurred_at
  from transactions t
  join people p on p.user_id = t.user_id, params
  where t.movement_type in ('gasto', 'pago_proveedor')
    and t.occurred_at >= params.since
    and (p_category is null or t.category = p_category)
),
demo as (
  select p.user_id,
         case when pr.gender is null or pr.gender = 'prefiero_no_decir' then 'sin_dato' else pr.gender end as gender,
         age_bucket(pr.age) as age_range
  from people p
  left join profiles pr on pr.id = p.user_id
),
spend_per_user as (
  select user_id, sum(amount) as total from expenses group by user_id
)
select case when (select count(*) from people) < (select k from params) then jsonb_build_object(
  'generated_at', now(), 'days', p_days, 'ruc', p_ruc, 'min_users', (select k from params),
  'filters', (select filters from params),
  'too_small', true,
  'summary', jsonb_build_object('people', (select count(*) from people), 'receipts', 0, 'receipts_total', 0,
                                'expenses_total', 0, 'points_issued', 0, 'redemptions', 0,
                                'consented_people', (select count(*) from consented))
) else jsonb_build_object(
  'generated_at', now(),
  'days', p_days,
  'ruc', p_ruc,
  'min_users', (select k from params),
  'filters', (select filters from params),
  'too_small', false,

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
    'avg_items_per_receipt', (
      select round(avg(n), 1) from (select count(*) as n from dgi_receipt_items i join receipts r on r.id = i.receipt_id group by i.receipt_id) b
    ),
    'consented_people', (select count(*) from consented),
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
             round(avg(amount), 2) as avg_ticket,
             round(100.0 * count(*) / nullif((select count(*) from receipts where payment_method is not null), 0), 1) as share
      from (
        select r.user_id, r.amount,
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
  ), '[]'::jsonb),

  -- Dia del mes (efecto quincena: en Panama se cobra el 15 y el 30)
  'month_days', coalesce((
    select jsonb_agg(row_to_json(x) order by x.day)
    from (
      select extract(day from local_at)::int as day, count(*) as receipts,
             round(sum(amount), 2) as total, round(avg(amount), 2) as avg_ticket
      from receipts group by 1
    ) x
  ), '[]'::jsonb),

  -- Momento del dia
  'dayparts', coalesce((
    select jsonb_agg(row_to_json(x) order by x.sort)
    from (
      select case when h < 6 then 5 when h < 11 then 1 when h < 14 then 2 when h < 18 then 3 else 4 end as sort,
             case when h < 6 then 'Madrugada (0–6)' when h < 11 then 'Mañana (6–11)' when h < 14 then 'Mediodía (11–14)'
                  when h < 18 then 'Tarde (14–18)' else 'Noche (18–24)' end as daypart,
             count(*) as receipts, round(sum(amount), 2) as total, round(avg(amount), 2) as avg_ticket
      from (select extract(hour from local_at)::int as h, amount from receipts) z
      group by 1, 2
    ) x
  ), '[]'::jsonb),

  -- Frecuencia de compra por persona en la ventana
  'frequency', coalesce((
    select jsonb_agg(row_to_json(x) order by x.sort)
    from (
      select case when visits = 1 then 1 when visits <= 3 then 2 when visits <= 9 then 3 else 4 end as sort,
             case when visits = 1 then '1 compra' when visits <= 3 then '2–3 compras'
                  when visits <= 9 then '4–9 compras' else '10 o más' end as bucket,
             count(*) as people
      from (select user_id, count(*) as visits from receipts group by user_id) v
      group by 1, 2
      having count(*) >= (select k from params)
    ) x
  ), '[]'::jsonb),

  -- Donde mas compran tambien los clientes de este comercio (solo con p_ruc)
  'also_shop_at', coalesce((
    select jsonb_agg(row_to_json(x) order by x.people desc)
    from (
      select r.ruc, coalesce(max(r.merchant_name), 'RUC ' || r.ruc) as merchant,
             count(distinct r.user_id) as people, count(*) as visits,
             round(sum(r.confirmed_amount), 2) as total
      from dgi_receipts r, params
      where p_ruc is not null
        and r.ruc <> p_ruc
        and r.status = 'confirmada'
        and r.confirmed_amount is not null
        and coalesce(r.authorized_at, r.scanned_at) >= params.since
        and r.user_id in (select user_id from people)
      group by r.ruc
      having count(distinct r.user_id) >= (select k from params)
      order by count(distinct r.user_id) desc
      limit 15
    ) x
  ), '[]'::jsonb),

  -- Medio de pago por genero (cruce para campañas)
  'payment_by_gender', coalesce((
    select jsonb_agg(row_to_json(x))
    from (
      select d.gender,
             case when r.payment_method ilike any (array['%tarjeta%', '%crédito%', '%credito%', '%débito%', '%debito%']) then 'Tarjeta'
                  when r.payment_method ilike '%efectivo%' then 'Efectivo'
                  else 'Otro' end as method,
             count(*) as receipts, count(distinct r.user_id) as people, round(avg(r.amount), 2) as avg_ticket
      from receipts r join demo d on d.user_id = r.user_id
      where r.payment_method is not null
      group by 1, 2
      having count(distinct r.user_id) >= (select k from params)
    ) x
  ), '[]'::jsonb)
)
end;
$$;

revoke execute on function public.market_insights(integer, text, integer, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.market_insights(integer, text, integer, text, text, text, text, text) to service_role;

-- Quien ya habia aceptado escanear facturas acepto el programa de
-- recompensas; el estudio de mercado se le vuelve a preguntar (opt-in).
insert into public.user_consents (user_id, purpose, granted, text_version, source)
select id, 'programa_recompensas', true, 1, 'app' from public.profiles where dgi_scan_consent_at is not null;
