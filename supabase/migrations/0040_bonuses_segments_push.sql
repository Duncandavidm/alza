-- Bonos y regalos a clientes segmentados, notificaciones push segmentadas,
-- probador de palabras de campañas y canje rapido en caja.
--
-- Consentimiento: Apple (guia 4.5.4) solo permite push de promociones a
-- quien lo acepto expresamente, con opcion de salirse en la app. Por eso
-- TODO lo segmentado (push y bonos) va solo a personas con el
-- consentimiento 'ofertas' vigente.

-- ------------------------------------------------------------------ base
alter table public.user_consents drop constraint user_consents_purpose_check;
alter table public.user_consents add constraint user_consents_purpose_check
  check (purpose in ('estudio_mercado', 'programa_recompensas', 'ofertas'));

alter table public.points_ledger drop constraint points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check
  check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje', 'canje_puntos',
                    'marca', 'marca_puntos', 'bono', 'bono_puntos'));

create or replace view public.points_balances
  with (security_invoker = true)
  as
  select
    user_id,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca', 'bono')), 0) as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca', 'bono')), 0) as pending_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('habito', 'canje_puntos', 'marca_puntos', 'bono_puntos')), 0) as habit_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source = 'habito' and points > 0), 0) as habit_points_earned
  from public.points_ledger
  group by user_id;

-- Un regalo de MonAvi es un "canje" ya emitido que no le costo nada al
-- cliente: al vencer NO se devuelve nada.
alter table public.reward_redemptions
  add column source text not null default 'canje' check (source in ('canje', 'regalo')),
  add column bonus_id uuid,
  add column gift_message text;

create or replace function public.release_redemption(p_redemption_id uuid, p_status text)
returns public.reward_redemptions
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_row public.reward_redemptions;
begin
  if p_status not in ('cancelado', 'vencido') then
    raise exception 'release_redemption: status invalido %', p_status;
  end if;

  update public.reward_redemptions
    set status = p_status
    where id = p_redemption_id and status = 'emitido'
    returning * into v_row;
  if v_row.id is null then
    select * into v_row from public.reward_redemptions where id = p_redemption_id;
    return v_row;
  end if;

  if v_row.source = 'regalo' then
    return v_row;
  end if;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (
    v_row.user_id,
    case when v_row.currency = 'puntos' then 'canje_puntos' else 'canje' end,
    'canje:' || v_row.id || ':devolucion',
    v_row.points_cost,
    'confirmado',
    jsonb_build_object('reason', p_status)
  )
  on conflict (source, external_ref) do nothing;

  return v_row;
end $$;

-- Codigo de canje unico de 6 caracteres (sin 0/O/1/I para no confundir).
create or replace function public.new_redemption_code() returns text
language plpgsql set search_path = public, pg_temp as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  i integer;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reward_redemptions where code = v_code);
  end loop;
  return v_code;
end $$;
revoke execute on function public.new_redemption_code() from public, anon, authenticated;

-- ------------------------------------------------------------ segmentos
-- p_segment (jsonb, todo opcional):
--   gender          femenino | masculino | otro
--   age_range       18-24 | 25-34 | 35-44 | 45-54 | 55+
--   days            ventana en dias (30 por defecto)
--   activity        mas_activos | menos_activos | inactivos | top_facturas
--   min_receipts    minimo de facturas verificadas en la ventana
--   bought_product  texto en el detalle de sus facturas (ej. "coca cola")
--   merchant_ruc    compro en este comercio (RUC)
--   payment         tarjeta | efectivo
--   min_cashback    saldo de cashback minimo (centavos)
-- Siempre: solo personas con el consentimiento 'ofertas' vigente.
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
    coalesce((p_segment->>'min_cashback')::int, 0) as min_cashback
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
            and r.scanned_at >= now() - make_interval(days => s.days)) as receipts
  from consented c
),
ranked as (
  select a.*,
         percent_rank() over (order by a.logged_days) as activity_rank,
         percent_rank() over (order by a.receipts) as receipts_rank
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
       or (s.activity = 'top_facturas' and r.receipts > 0 and r.receipts_rank >= 0.8))
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
          and ((s.payment = 'tarjeta' and d.payment_method ilike any (array['%tarjeta%', '%crédito%', '%credito%', '%débito%', '%debito%']))
               or (s.payment = 'efectivo' and d.payment_method ilike '%efectivo%'))))
  and (s.min_cashback <= 0 or coalesce((select b.confirmed_points from points_balances b where b.user_id = r.user_id), 0) >= s.min_cashback);
$$;
revoke execute on function public.segment_user_ids(jsonb) from public, anon, authenticated;

create or replace function public.segment_preview(p_segment jsonb default '{}'::jsonb)
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'people', count(*),
    'with_push', count(*) filter (where exists (select 1 from device_push_tokens t where t.user_id = s.user_id)),
    'consented_total', (select count(*) from current_consents c where c.purpose = 'ofertas' and c.granted)
  )
  from segment_user_ids(p_segment) s;
$$;
revoke execute on function public.segment_preview(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------- push segmentado
create table public.push_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 240),
  -- Pantalla que abre al tocarla: points | rewards | redemptions | home
  screen text not null default 'home' check (screen in ('home', 'points', 'rewards', 'redemptions')),
  segment jsonb not null default '{}'::jsonb,
  brand_campaign_id uuid references public.brand_campaigns (id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'sending', 'sent', 'failed')),
  target_count integer not null default 0,
  sent_count integer not null default 0,
  failed_count integer not null default 0,
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.push_campaigns enable row level security;

-- ---------------------------------------------------------- bonos/regalos
create table public.bonus_grants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- cashback: suma centavos al cashback | puntos: suma puntos |
  -- cupon: regala un producto de un comercio (codigo listo para canjear)
  kind text not null check (kind in ('cashback', 'puntos', 'cupon')),
  amount integer check (amount is null or amount > 0),
  reward_item_id uuid references public.reward_items (id) on delete restrict,
  message text,
  expires_days integer not null default 30 check (expires_days between 1 and 365),
  segment jsonb not null default '{}'::jsonb,
  notify boolean not null default true,
  status text not null default 'draft' check (status in ('draft', 'granted')),
  granted_count integer not null default 0,
  created_at timestamptz not null default now(),
  granted_at timestamptz,
  check ((kind in ('cashback', 'puntos') and amount is not null) or (kind = 'cupon' and reward_item_id is not null))
);
alter table public.bonus_grants enable row level security;

create table public.bonus_recipients (
  bonus_id uuid not null references public.bonus_grants (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  redemption_id uuid references public.reward_redemptions (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (bonus_id, user_id)
);
create index bonus_recipients_user_idx on public.bonus_recipients (user_id);
alter table public.bonus_recipients enable row level security;
create policy "bonus_recipients_select_own" on public.bonus_recipients
  for select to authenticated using (user_id = (select auth.uid()));

-- Entrega el bono a todo el segmento (idempotente por persona).
create or replace function public.grant_bonus(p_bonus_id uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
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

  for v_user in select s.user_id from public.segment_user_ids(v_bonus.segment) s loop
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
end $$;
revoke execute on function public.grant_bonus(uuid) from public, anon, authenticated;

-- ------------------------------------------- probador de palabras (marcas)
-- Que lineas reales de factura atraparia una campaña con estas palabras.
-- Solo descripciones de productos y conteos, nunca personas.
create or replace function public.campaign_keyword_matches(p_keywords text[], p_days integer default 90)
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.times desc), '[]'::jsonb)
  from (
    select upper(trim(i.description)) as description, count(*) as times,
           round(sum(coalesce(i.quantity, 1)), 0) as units
    from dgi_receipt_items i
    join dgi_receipts r on r.id = i.receipt_id
    where r.status = 'confirmada'
      and r.scanned_at >= now() - make_interval(days => greatest(p_days, 1))
      and exists (
        select 1 from unnest(p_keywords) k
        where length(trim(k)) >= 3
          and translate(lower(i.description), 'áéíóúü', 'aeiouu')
              like '%' || translate(lower(trim(k)), 'áéíóúü', 'aeiouu') || '%')
    group by upper(trim(i.description))
    order by count(*) desc
    limit 40
  ) x;
$$;
revoke execute on function public.campaign_keyword_matches(text[], integer) from public, anon, authenticated;

-- ------------------------------------------------- canje rapido en caja
-- El PIN se pide una vez por turno: el panel guarda una sesion firmada
-- del comercio y luego solo escanea. Este RPC confia en el merchant_id que
-- le pasa el panel (service role) y exige que el codigo sea de ese comercio.
create or replace function public.merchant_redeem_session(
  p_code text, p_merchant_id uuid, p_ip_hash text, p_confirm boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_redemption public.reward_redemptions;
  v_updated public.reward_redemptions;
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_failures integer;
begin
  select count(*) into v_failures from public.redeem_attempts
   where ip_hash = coalesce(p_ip_hash, 'desconocida') and not success and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_merchant from public.partner_merchants where id = p_merchant_id;
  select * into v_redemption from public.reward_redemptions where code = v_code;
  if v_merchant.id is null or v_redemption.id is null or v_redemption.merchant_id <> v_merchant.id then
    insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), v_code, false);
    return jsonb_build_object('ok', false, 'error',
      case when v_redemption.id is not null and v_merchant.id is not null
           then 'Este código es de otro comercio.' else 'Código no encontrado.' end);
  end if;
  insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), v_code, true);

  select * into v_item from public.reward_items where id = v_redemption.reward_item_id;

  if v_redemption.status = 'entregado' then
    return jsonb_build_object('ok', false, 'product', v_item.name, 'error', 'Este código ya se usó el ' ||
      to_char(v_redemption.delivered_at at time zone 'America/Panama', 'DD/MM/YYYY "a las" HH24:MI') || '.');
  end if;
  if v_redemption.status in ('cancelado', 'vencido') or v_redemption.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'Este código está vencido o fue cancelado.', 'product', v_item.name);
  end if;

  if p_confirm then
    update public.reward_redemptions
       set status = 'entregado', delivered_at = now(), delivered_via = 'comercio'
     where id = v_redemption.id and status = 'emitido' and expires_at >= now()
    returning * into v_updated;
    if v_updated.id is null then
      return jsonb_build_object('ok', false, 'error', 'No se pudo confirmar el canje. Intenta de nuevo.');
    end if;
    v_redemption := v_updated;
  end if;

  return jsonb_build_object(
    'ok', true, 'delivered', p_confirm, 'code', v_code, 'product', v_item.name, 'photo_url', v_item.photo_url,
    'merchant', v_merchant.name, 'merchant_id', v_merchant.id, 'currency', v_redemption.currency,
    'value', v_redemption.points_cost, 'value_cents', v_redemption.points_cost, 'is_gift', v_redemption.source = 'regalo',
    'expires_at', v_redemption.expires_at, 'delivered_at', v_redemption.delivered_at);
end $$;
revoke execute on function public.merchant_redeem_session(text, uuid, text, boolean) from public, anon, authenticated;
