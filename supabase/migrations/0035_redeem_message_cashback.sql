-- Cashback: el mensaje de saldo insuficiente al canjear ya no habla de
-- "puntos" (la app muestra cashback en dolares; 1 punto = US$0.01).
create or replace function public.redeem_reward(p_item_id uuid)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_item public.reward_items;
  v_merchant_status text;
  v_balance integer;
  v_code text;
  v_row public.reward_redemptions;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));

  select * into v_item from public.reward_items where id = p_item_id;
  if v_item.id is null or v_item.status <> 'active' then
    raise exception 'Este producto ya no está disponible' using errcode = 'P0001';
  end if;
  select status into v_merchant_status from public.partner_merchants where id = v_item.merchant_id;
  if v_merchant_status is distinct from 'active' then
    raise exception 'Este comercio ya no está disponible' using errcode = 'P0001';
  end if;

  select coalesce(sum(points), 0) into v_balance
    from public.points_ledger
    where user_id = v_user and status = 'confirmado' and source <> 'habito';
  if v_balance < v_item.points_cost then
    raise exception 'No tienes cashback suficiente para este canje' using errcode = 'P0001';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reward_redemptions where code = v_code);
  end loop;

  insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code)
  values (v_user, v_item.id, v_item.merchant_id, v_item.points_cost, v_code)
  returning * into v_row;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (
    v_user, 'canje', 'canje:' || v_row.id, -v_item.points_cost, 'confirmado',
    jsonb_build_object('rewardItemId', v_item.id, 'rewardName', v_item.name, 'code', v_code)
  );

  return v_row;
end;
$$;

