-- Canjes con cupo y canjes de descuento.
--
-- 1) Cupo (max_redemptions): el comercio dice cuantos puede dar (ej. 20
--    capuchinos). El canje se ve para todos; cuando se emite el codigo
--    numero 20 el producto pasa a 'agotado' y la RLS lo esconde de la app
--    (sin actualizar la app). Cuentan los codigos emitidos y entregados de
--    canjes normales; los regalos de MonAvi (source 'regalo') no gastan
--    cupo. Si un codigo vence o se cancela, el cupo vuelve y el producto se
--    reactiva solo.
--
-- 2) Tipo (reward_type): 'producto' (como hasta ahora), 'porcentaje'
--    (ej. 10% de descuento) o 'monto' (cupon de US$20). discount_value
--    guarda el 10 o el 20. El nombre se arma en el panel ("10% de
--    descuento", "Cupón de $20") para que las versiones actuales de la app
--    lo muestren bien sin cambios.

alter table public.reward_items
  add column if not exists max_redemptions integer,
  add column if not exists reward_type text not null default 'producto',
  add column if not exists discount_value numeric(10, 2);

alter table public.reward_items drop constraint if exists reward_items_status_check;
alter table public.reward_items
  add constraint reward_items_status_check check (status in ('active', 'paused', 'agotado'));

alter table public.reward_items drop constraint if exists reward_items_max_redemptions_check;
alter table public.reward_items
  add constraint reward_items_max_redemptions_check check (max_redemptions is null or max_redemptions between 1 and 1000000);

alter table public.reward_items drop constraint if exists reward_items_reward_type_check;
alter table public.reward_items
  add constraint reward_items_reward_type_check check (
    (reward_type = 'producto' and discount_value is null)
    or (reward_type = 'porcentaje' and discount_value > 0 and discount_value <= 100)
    or (reward_type = 'monto' and discount_value > 0 and discount_value <= 100000)
  );

-- Codigos que gastan cupo de un producto.
create or replace function public.reward_item_used(p_item_id uuid)
returns integer
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select count(*)::int from public.reward_redemptions
  where reward_item_id = p_item_id
    and source <> 'regalo'
    and status in ('emitido', 'entregado');
$$;
revoke all on function public.reward_item_used(uuid) from public, anon, authenticated;

-- Estado segun el cupo: un producto activo o agotado se recalcula en cada
-- cambio (tambien cuando el panel sube el cupo o lo quita). Pausado se
-- respeta tal cual.
create or replace function public.reward_items_apply_stock()
returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if new.status in ('active', 'agotado') then
    if new.max_redemptions is null then
      new.status := 'active';
    else
      new.status := case when public.reward_item_used(new.id) >= new.max_redemptions then 'agotado' else 'active' end;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists reward_items_apply_stock on public.reward_items;
create trigger reward_items_apply_stock
  before insert or update on public.reward_items
  for each row execute function public.reward_items_apply_stock();

-- Cada codigo emitido, entregado, vencido o cancelado vuelve a calcular el
-- estado de su producto (solo si tiene cupo).
create or replace function public.reward_redemptions_touch_stock()
returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  update public.reward_items
     set updated_at = now()
   where id = new.reward_item_id and max_redemptions is not null;
  return null;
end $$;

drop trigger if exists reward_redemptions_touch_stock on public.reward_redemptions;
create trigger reward_redemptions_touch_stock
  after insert or update of status on public.reward_redemptions
  for each row execute function public.reward_redemptions_touch_stock();

-- redeem_reward: igual que antes, mas el cupo. El producto se bloquea
-- (for update) para que dos personas no se lleven el ultimo a la vez.
create or replace function public.redeem_reward(p_item_id uuid)
 returns reward_redemptions
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
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
    raise exception 'Este producto ya no está disponible' using errcode = 'P0001';
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
      raise exception 'No tienes puntos suficientes para este canje' using errcode = 'P0001';
    else
      raise exception 'No tienes cashback suficiente para este canje' using errcode = 'P0001';
    end if;
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reward_redemptions where code = v_code);
  end loop;

  insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code, currency)
  values (v_user, v_item.id, v_item.merchant_id, v_item.points_cost, v_code, v_merchant.reward_currency)
  returning * into v_row;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (
    v_user,
    case when v_merchant.reward_currency = 'puntos' then 'canje_puntos' else 'canje' end,
    'canje:' || v_row.id,
    -v_item.points_cost,
    'confirmado',
    jsonb_build_object('rewardItemId', v_item.id, 'rewardName', v_item.name, 'code', v_code)
  );

  return v_row;
end;
$function$;

-- Caja: devuelve tambien el tipo para decir "Aplicar 10% de descuento" en
-- vez de "Entregar". Resto igual que 0049/0050.
create or replace function public.merchant_redeem_session(p_code text, p_merchant_id uuid, p_ip_hash text, p_confirm boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
    'reward_type', v_item.reward_type, 'discount_value', v_item.discount_value,
    'merchant', v_merchant.name, 'merchant_id', v_merchant.id, 'currency', v_redemption.currency,
    'value', v_redemption.points_cost, 'value_cents', v_redemption.points_cost, 'is_gift', v_redemption.source = 'regalo',
    'expires_at', v_redemption.expires_at, 'delivered_at', v_redemption.delivered_at);
end $function$;

create or replace function public.merchant_redeem(p_code text, p_pin text, p_ip_hash text, p_confirm boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_failures integer;
  v_redemption public.reward_redemptions;
  v_updated public.reward_redemptions;
  v_item public.reward_items;
  v_merchant public.partner_merchants;
begin
  select count(*) into v_failures
    from public.redeem_attempts
    where ip_hash = coalesce(p_ip_hash, 'desconocida')
      and not success
      and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_redemption from public.reward_redemptions where code = v_code;
  if v_redemption.id is not null then
    select * into v_merchant from public.partner_merchants where id = v_redemption.merchant_id;
  end if;

  if v_redemption.id is null
     or v_merchant.redeem_pin_hash is null
     or v_merchant.redeem_pin_hash <> crypt(coalesce(p_pin, ''), v_merchant.redeem_pin_hash) then
    insert into public.redeem_attempts (ip_hash, code, success)
      values (coalesce(p_ip_hash, 'desconocida'), v_code, false);
    return jsonb_build_object('ok', false, 'error', 'Código o PIN incorrecto.');
  end if;

  insert into public.redeem_attempts (ip_hash, code, success)
    values (coalesce(p_ip_hash, 'desconocida'), v_code, true);

  select * into v_item from public.reward_items where id = v_redemption.reward_item_id;

  if v_redemption.status = 'entregado' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Este código ya se usó el ' ||
        to_char(v_redemption.delivered_at at time zone 'America/Panama', 'DD/MM/YYYY "a las" HH24:MI') || '.',
      'product', v_item.name
    );
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
    'ok', true,
    'delivered', p_confirm,
    'code', v_code,
    'product', v_item.name,
    'photo_url', v_item.photo_url,
    'reward_type', v_item.reward_type,
    'discount_value', v_item.discount_value,
    'merchant', v_merchant.name, 'merchant_id', v_merchant.id, 'is_gift', v_redemption.source = 'regalo',
    'currency', v_redemption.currency,
    'value', v_redemption.points_cost,
    'value_cents', v_redemption.points_cost,
    'expires_at', v_redemption.expires_at,
    'delivered_at', v_redemption.delivered_at
  );
end;
$function$;
