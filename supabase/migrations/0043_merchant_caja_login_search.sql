-- MonAvi Caja (PWA del comercio): iniciar turno con RUC + PIN y buscar
-- clientes con canjes/regalos pendientes en ESE comercio.
--
-- Privacidad: el comercio solo ve a clientes que tienen un canje o regalo
-- pendiente en su local, y solo el nombre de pila + inicial del apellido y
-- los ultimos 4 digitos del telefono (para confirmar que es la persona).

create or replace function public.merchant_login(p_ruc text, p_pin text, p_ip_hash text)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_merchant public.partner_merchants;
  v_failures integer;
begin
  select count(*) into v_failures from public.redeem_attempts
   where ip_hash = coalesce(p_ip_hash, 'desconocida') and not success and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_merchant from public.partner_merchants
   where upper(regexp_replace(ruc, '\s', '', 'g')) = upper(regexp_replace(coalesce(p_ruc, ''), '\s', '', 'g'))
     and status = 'active';

  if v_merchant.id is null or v_merchant.redeem_pin_hash is null
     or v_merchant.redeem_pin_hash <> crypt(coalesce(p_pin, ''), v_merchant.redeem_pin_hash) then
    insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), 'LOGIN', false);
    return jsonb_build_object('ok', false, 'error', 'RUC o PIN incorrecto.');
  end if;

  insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), 'LOGIN', true);
  return jsonb_build_object('ok', true, 'merchant_id', v_merchant.id, 'merchant', v_merchant.name);
end $$;
revoke execute on function public.merchant_login(text, text, text) from public, anon, authenticated;

create or replace function public.merchant_pending_redemptions(p_merchant_id uuid, p_query text default null)
returns jsonb
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.expires_at), '[]'::jsonb)
  from (
    select rr.code,
           ri.name as product,
           ri.photo_url,
           rr.source = 'regalo' as is_gift,
           rr.expires_at,
           trim(split_part(coalesce(nullif(p.full_name, ''), 'Cliente'), ' ', 1) || ' ' ||
                coalesce(left(nullif(split_part(p.full_name, ' ', 2), ''), 1) || '.', '')) as customer,
           case when p.phone is not null then '•••• ' || right(regexp_replace(p.phone, '\D', '', 'g'), 4) end as phone_hint
    from public.reward_redemptions rr
    join public.reward_items ri on ri.id = rr.reward_item_id
    left join public.profiles p on p.id = rr.user_id
    left join auth.users u on u.id = rr.user_id
    where rr.merchant_id = p_merchant_id
      and rr.status = 'emitido'
      and rr.expires_at >= now()
      and (
        coalesce(trim(p_query), '') = ''
        or rr.code ilike '%' || trim(p_query) || '%'
        or p.full_name ilike '%' || trim(p_query) || '%'
        or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || regexp_replace(trim(p_query), '\D', '', 'g') || '%'
           and length(regexp_replace(trim(p_query), '\D', '', 'g')) >= 4
        or (length(trim(p_query)) >= 5 and u.email ilike trim(p_query) || '%')
      )
    order by rr.expires_at
    limit 30
  ) x;
$$;
revoke execute on function public.merchant_pending_redemptions(uuid, text) from public, anon, authenticated;
