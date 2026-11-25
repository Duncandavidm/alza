-- 0085: el cashback desbloquea descuentos y bonos.
--
-- Un beneficio de un comercio aliado (reward_items) puede ser:
--   - descuento en % (reward_type 'porcentaje') o bono en US$ ('monto');
--   - gratis (free_benefit) o desbloqueable con cashback (points_cost > 0).
-- Esto agrega:
--   - unlock_valid_days: dias para usarlo despues de desbloquearlo (7 por
--     defecto). Si vence sin usarse, el cashback se devuelve (como siempre).
--   - min_purchase: compra minima (opcional) que el cajero ve al validar.
--   - funded_by: quien paga el bono ('comercio' o 'monavi'). Los bonos que
--     paga MonAvi se liquidan al comercio (monavi_bono_settlement).
--   - available_from / available_until: fechas de la promocion (opcional).

alter table public.reward_items
  add column if not exists unlock_valid_days integer not null default 7,
  add column if not exists min_purchase numeric(10,2),
  add column if not exists funded_by text not null default 'comercio',
  add column if not exists available_from timestamptz,
  add column if not exists available_until timestamptz;

alter table public.reward_items drop constraint if exists reward_items_unlock_valid_days_check;
alter table public.reward_items add constraint reward_items_unlock_valid_days_check
  check (unlock_valid_days between 1 and 90);
alter table public.reward_items drop constraint if exists reward_items_min_purchase_check;
alter table public.reward_items add constraint reward_items_min_purchase_check
  check (min_purchase is null or (min_purchase > 0 and min_purchase <= 100000));
alter table public.reward_items drop constraint if exists reward_items_funded_by_check;
alter table public.reward_items add constraint reward_items_funded_by_check
  check (funded_by in ('comercio', 'monavi'));
alter table public.reward_items drop constraint if exists reward_items_window_check;
alter table public.reward_items add constraint reward_items_window_check
  check (available_from is null or available_until is null or available_until > available_from);

-- true si la promocion esta dentro de sus fechas (sin fechas = siempre).
create or replace function public.reward_item_in_window(p_item public.reward_items)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select (p_item.available_from is null or p_item.available_from <= now())
     and (p_item.available_until is null or p_item.available_until > now());
$$;

-- ---------------------------------------------------------------------------
-- Desbloquear con cashback: igual que antes + fechas + dias de validez.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_reward(p_item_id uuid)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_balance integer;
  v_code text;
  v_row public.reward_redemptions;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;

  if not public.email_is_verified(v_user) then
    raise exception 'Verifica tu correo para canjear' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));

  select * into v_item from public.reward_items where id = p_item_id for update;
  if v_item.id is not null and v_item.status = 'agotado' then
    raise exception 'Se agotó: ya se canjearon todos los disponibles' using errcode = 'P0001';
  end if;
  if v_item.id is null or v_item.status <> 'active' then
    raise exception 'Este beneficio ya no está disponible' using errcode = 'P0001';
  end if;
  if v_item.available_from is not null and v_item.available_from > now() then
    raise exception 'Esta promoción todavía no empieza' using errcode = 'P0001';
  end if;
  if v_item.available_until is not null and v_item.available_until <= now() then
    raise exception 'Esta promoción ya terminó' using errcode = 'P0001';
  end if;
  if v_item.max_redemptions is not null and public.reward_item_used(v_item.id) >= v_item.max_redemptions then
    raise exception 'Se agotó: ya se canjearon todos los disponibles' using errcode = 'P0001';
  end if;
  select * into v_merchant from public.partner_merchants where id = v_item.merchant_id;
  if v_merchant.id is null or v_merchant.status <> 'active' then
    raise exception 'Este comercio ya no está disponible' using errcode = 'P0001';
  end if;

  v_balance := public.reward_balance(v_user, v_merchant.reward_currency);
  if v_balance < v_item.points_cost then
    if v_merchant.reward_currency = 'puntos' then
      raise exception 'Todavía no te alcanza para este canje' using errcode = 'P0001';
    else
      raise exception 'No tienes cashback suficiente para desbloquearlo' using errcode = 'P0001';
    end if;
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reward_redemptions where code = v_code);
  end loop;

  insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, currency, expires_at)
  values (v_user, v_item.id, v_item.merchant_id, v_item.points_cost, v_code, v_merchant.reward_currency,
          now() + make_interval(days => coalesce(v_item.unlock_valid_days, 7)))
  returning * into v_row;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (
    v_user,
    case when v_merchant.reward_currency = 'puntos' then 'canje_puntos' else 'canje' end,
    'canje:' || v_row.id,
    -v_item.points_cost,
    'confirmado',
    jsonb_build_object('rewardItemId', v_item.id, 'rewardName', v_item.name, 'code', v_code,
                       'rewardType', v_item.reward_type)
  );

  return v_row;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Descuentos y bonos gratis: igual que antes + fechas de la promocion.
-- ---------------------------------------------------------------------------
create or replace function public.use_benefit(p_item_id uuid)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_row public.reward_redemptions;
  v_next timestamptz;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  if not public.email_is_verified(v_user) then
    raise exception 'Verifica tu correo para usar este descuento' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));

  select * into v_item from public.reward_items where id = p_item_id for update;
  if v_item.id is null or not v_item.free_benefit then
    raise exception 'Este descuento ya no está disponible' using errcode = 'P0001';
  end if;
  if v_item.status = 'agotado' then
    raise exception 'Se agotó: ya se usaron todos los disponibles' using errcode = 'P0001';
  end if;
  if v_item.status <> 'active' then
    raise exception 'Este descuento ya no está disponible' using errcode = 'P0001';
  end if;
  if v_item.available_from is not null and v_item.available_from > now() then
    raise exception 'Esta promoción todavía no empieza' using errcode = 'P0001';
  end if;
  if v_item.available_until is not null and v_item.available_until <= now() then
    raise exception 'Esta promoción ya terminó' using errcode = 'P0001';
  end if;
  select * into v_merchant from public.partner_merchants where id = v_item.merchant_id;
  if v_merchant.id is null or v_merchant.status <> 'active' then
    raise exception 'Este comercio ya no está disponible' using errcode = 'P0001';
  end if;

  if not public.has_scanned_receipt(v_user) then
    raise exception 'Escanea tu primera factura fiscal para desbloquear los descuentos' using errcode = 'P0001';
  end if;

  select * into v_row from public.reward_redemptions
   where user_id = v_user and reward_item_id = v_item.id and source = 'beneficio'
     and status = 'emitido' and expires_at > now()
   order by created_at desc limit 1;
  if v_row.id is not null then
    return v_row;
  end if;

  if public.benefit_uses_in_period(v_user, v_item) >= v_item.per_user_limit then
    v_next := public.benefit_period_end(v_item.per_user_period);
    raise exception '%', case
      when v_next is null then 'Ya usaste este descuento.'
      else 'Ya usaste este descuento ' ||
        case v_item.per_user_period when 'dia' then 'hoy' when 'semana' then 'esta semana' else 'este mes' end ||
        '. Vuelve a estar disponible el ' || to_char(v_next at time zone 'America/Panama', 'DD/MM') || '.'
      end using errcode = 'P0001';
  end if;

  if v_item.max_redemptions is not null and public.reward_item_used(v_item.id) >= v_item.max_redemptions then
    raise exception 'Se agotó: ya se usaron todos los disponibles' using errcode = 'P0001';
  end if;

  insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, status,
      expires_at, currency, source)
  values (v_user, v_item.id, v_item.merchant_id, 0, public.new_redemption_code(), 'emitido',
      now() + interval '15 minutes', v_merchant.reward_currency, 'beneficio')
  returning * into v_row;
  return v_row;
end $function$;

-- ---------------------------------------------------------------------------
-- "Ya te alcanza para desbloquear…": solo promociones vigentes, y con el
-- tipo y valor para armar el texto ("20% de descuento", "bono de $20").
-- ---------------------------------------------------------------------------
create or replace function public.reward_unlocks_to_notify()
returns table(user_id uuid, items jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
begin
  delete from public.reward_unlock_notifications n
  using public.reward_items ri, public.partner_merchants pm
  where ri.id = n.reward_item_id
    and pm.id = ri.merchant_id
    and public.reward_balance(n.user_id, pm.reward_currency) < ri.points_cost;

  return query
  with users_with_tokens as (
    select distinct t.user_id from public.device_push_tokens t
  ),
  affordable as (
    select u.user_id, ri.id as item_id, ri.name, pm.name as merchant, ri.points_cost, pm.reward_currency,
           ri.reward_type, ri.discount_value
    from users_with_tokens u
    cross join public.reward_items ri
    join public.partner_merchants pm on pm.id = ri.merchant_id
    where ri.status = 'active' and pm.status = 'active' and not ri.free_benefit and ri.audience = 'catalogo'
      and public.reward_item_in_window(ri)
      and public.reward_balance(u.user_id, pm.reward_currency) >= ri.points_cost
      and not exists (
        select 1 from public.reward_unlock_notifications n
        where n.user_id = u.user_id and n.reward_item_id = ri.id
      )
  )
  select a.user_id,
         jsonb_agg(jsonb_build_object(
           'id', a.item_id, 'name', a.name, 'merchant', a.merchant,
           'cost', a.points_cost, 'currency', a.reward_currency,
           'type', a.reward_type, 'value', a.discount_value
         ) order by a.points_cost desc)
  from affordable a
  group by a.user_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Caja: ademas devuelve la compra minima y quien paga el bono.
-- ---------------------------------------------------------------------------
create or replace function public.merchant_redeem_session(p_code text, p_merchant_id uuid, p_ip_hash text,
    p_confirm boolean default false, p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_redemption public.reward_redemptions;
  v_updated public.reward_redemptions;
  v_item public.reward_items;
  v_merchant public.partner_merchants;
  v_failures integer;
  v_branch uuid;
begin
  select count(*) into v_failures from public.redeem_attempts
   where ip_hash = coalesce(p_ip_hash, 'desconocida') and not success and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_merchant from public.partner_merchants where id = p_merchant_id;
  select b.id into v_branch from public.merchant_branches b where b.id = p_branch_id and b.merchant_id = p_merchant_id;
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
    return jsonb_build_object('ok', false, 'error', case when v_redemption.source = 'beneficio' and v_redemption.status <> 'cancelado' then 'Este código de descuento ya venció (dura 15 minutos). Pídele al cliente que genere uno nuevo en la app.' else 'Este código está vencido o fue cancelado.' end, 'product', v_item.name);
  end if;

  if p_confirm then
    update public.reward_redemptions
       set status = 'entregado', delivered_at = now(), delivered_via = 'comercio', branch_id = v_branch
     where id = v_redemption.id and status = 'emitido' and expires_at >= now()
    returning * into v_updated;
    if v_updated.id is null then
      return jsonb_build_object('ok', false, 'error', 'No se pudo confirmar el canje. Intenta de nuevo.');
    end if;
    v_redemption := v_updated;
  end if;

  return jsonb_build_object(
    'ok', true, 'delivered', p_confirm, 'code', v_code, 'product', v_item.name, 'photo_url', v_item.photo_url,
    'reward_type', v_item.reward_type, 'is_benefit', v_redemption.source = 'beneficio', 'discount_value', v_item.discount_value,
    'merchant', v_merchant.name, 'merchant_id', v_merchant.id, 'currency', v_redemption.currency,
    'branch_id', v_branch, 'branch', (select b.name from public.merchant_branches b where b.id = v_branch),
    'value', v_redemption.points_cost, 'value_cents', v_redemption.points_cost, 'is_gift', v_redemption.source = 'regalo',
    'expires_at', v_redemption.expires_at, 'delivered_at', v_redemption.delivered_at,
    'min_purchase', v_item.min_purchase, 'funded_by', v_item.funded_by);
end $function$;

-- ---------------------------------------------------------------------------
-- Liquidacion: bonos en US$ que paga MonAvi y que el comercio ya aplico
-- (desbloqueados con cashback o gratis; los cupones por habitos van en
-- coupon_settlement). Por mes y comercio, mas lo emitido pendiente.
-- ---------------------------------------------------------------------------
create or replace function public.monavi_bono_settlement(p_months integer default 6)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with bonos as (
    select rr.id, rr.merchant_id, rr.status, rr.expires_at, rr.delivered_at, ri.discount_value
    from public.reward_redemptions rr
    join public.reward_items ri on ri.id = rr.reward_item_id
    where ri.reward_type = 'monto' and ri.funded_by = 'monavi' and rr.source in ('canje', 'beneficio')
  ),
  pending as (
    select merchant_id, count(*) as outstanding, round(sum(discount_value), 2) as outstanding_usd
    from bonos
    where status = 'emitido' and expires_at >= now()
    group by merchant_id
  )
  select coalesce(jsonb_agg(row_to_json(x) order by x.month desc, x.merchant), '[]'::jsonb)
  from (
    select to_char(date_trunc('month', b.delivered_at at time zone 'America/Panama'), 'YYYY-MM') as month,
           pm.id as merchant_id, pm.name as merchant,
           count(*) as delivered,
           round(sum(b.discount_value), 2) as amount_usd,
           coalesce(max(p.outstanding), 0) as outstanding,
           coalesce(max(p.outstanding_usd), 0) as outstanding_usd
    from bonos b
    join public.partner_merchants pm on pm.id = b.merchant_id
    left join pending p on p.merchant_id = pm.id
    where b.status = 'entregado'
      and b.delivered_at >= date_trunc('month', now()) - make_interval(months => greatest(p_months, 1))
    group by 1, pm.id, pm.name
  ) x;
$function$;

revoke execute on function public.monavi_bono_settlement(integer) from public, anon, authenticated;
grant execute on function public.monavi_bono_settlement(integer) to service_role;
revoke execute on function public.merchant_redeem_session(text, uuid, text, boolean, uuid) from public, anon, authenticated;
grant execute on function public.merchant_redeem_session(text, uuid, text, boolean, uuid) to service_role;
revoke execute on function public.reward_unlocks_to_notify() from public, anon, authenticated;
grant execute on function public.reward_unlocks_to_notify() to service_role;

-- ---------------------------------------------------------------------------
-- Descuentos y bonos gratis de la app: solo los que estan dentro de sus
-- fechas (igual que antes en todo lo demas).
-- ---------------------------------------------------------------------------
create or replace function public.my_benefits()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'unlocked', coalesce(public.has_scanned_receipt(auth.uid()), false),
    'benefits', coalesce(jsonb_agg(jsonb_build_object(
        'item', to_jsonb(ri) || jsonb_build_object(
          'partner_merchants', (to_jsonb(pm) - 'redeem_pin_set_at' - 'announced_at') || jsonb_build_object(
            'merchant_branches', coalesce((
              select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'address', b.address,
                                                  'maps_url', b.maps_url, 'sort_order', b.sort_order)
                               order by b.sort_order, b.name)
              from public.merchant_branches b where b.merchant_id = pm.id and b.status = 'active'), '[]'::jsonb))),
        'uses_in_period', u.uses,
        'available_again_at', case when u.uses >= ri.per_user_limit
                                   then public.benefit_period_end(ri.per_user_period) end,
        'used_up', u.uses >= ri.per_user_limit and ri.per_user_period = 'siempre',
        'active_redemption', (
          select to_jsonb(rr) from public.reward_redemptions rr
          where rr.user_id = auth.uid() and rr.reward_item_id = ri.id and rr.source = 'beneficio'
            and rr.status = 'emitido' and rr.expires_at > now()
          order by rr.created_at desc limit 1)
      ) order by pm.name, ri.sort_order, ri.name), '[]'::jsonb)
  )
  from public.reward_items ri
  join public.partner_merchants pm on pm.id = ri.merchant_id
  cross join lateral (select public.benefit_uses_in_period(auth.uid(), ri) as uses) u
  where auth.uid() is not null and ri.free_benefit and ri.status = 'active' and pm.status = 'active'
    and public.reward_item_in_window(ri);
$function$;
