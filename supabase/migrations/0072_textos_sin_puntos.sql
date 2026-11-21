-- 0072: textos que ve el usuario sin "puntos" (1.0.3: solo cashback y
-- descuentos). Solo cambian mensajes; la logica queda igual.
--
-- - habit_rule_reason: la salud financiera es una nota de 0 a 100, no
--   puntos de recompensa: "de 70/100 o más".
-- - redeem_reward: el comercio de demostracion sigue canjeando con saldo
--   'puntos' hasta que se pase a cashback; el error ya no dice "puntos".

create or replace function public.habit_rule_reason(p_rule habit_coupon_rules)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select case p_rule.rule_type
    when 'ahorro_ingresos' then 'por ahorrar el ' || rtrim(to_char(p_rule.threshold, 'FM999990.##'), '.') || '% de tus ingresos en el mes'
    when 'meta_a_tiempo' then 'por cumplir una meta de ahorro a tiempo'
    when 'presupuestos' then 'por cumplir todos tus presupuestos del mes'
    when 'dias_registrados' then 'por anotar tus movimientos ' || trim(to_char(p_rule.threshold, 'FM990')) || ' días del mes'
    when 'todos' then 'por ser de MonAvi'
    else 'por tener una salud financiera de ' || trim(to_char(p_rule.threshold, 'FM990')) || '/100 o más'
  end;
$function$;

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
      raise exception 'Todavía no te alcanza para este canje' using errcode = 'P0001';
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
