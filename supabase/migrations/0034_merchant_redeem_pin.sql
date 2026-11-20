-- Canje en caja: el comercio valida el codigo del cliente con su PIN.
--
-- Flujo: el cajero abre monavi.maday.app/canjear, escribe (o escanea) el
-- codigo de 6 caracteres que le muestra el cliente y el PIN de 6 digitos
-- de su comercio. merchant_redeem() verifica que el codigo sea de ESE
-- comercio, que siga vigente y que no se haya usado, y lo marca como
-- entregado. El PIN se guarda solo como hash bcrypt (nunca en claro) y
-- se limitan los intentos fallidos por IP para que no se pueda adivinar.
--
-- Cashback: el ledger sigue en enteros; 1 punto = US$0.01. La regla
-- actual (points_per_dollar = 1) equivale a 1% de cashback por cada
-- factura verificada, y el tope diario de 300 equivale a US$3.00.

alter table public.partner_merchants
  add column redeem_pin_hash text,
  add column redeem_pin_set_at timestamptz;

alter table public.reward_redemptions
  add column delivered_via text check (delivered_via in ('comercio', 'panel'));

create table public.redeem_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  code text,
  success boolean not null,
  created_at timestamptz not null default now()
);

create index redeem_attempts_ip_idx on public.redeem_attempts (ip_hash, created_at);

-- Sin policies: solo las funciones de abajo (security definer) escriben.
alter table public.redeem_attempts enable row level security;

-- El panel genera el PIN (6 digitos) y lo muestra una sola vez.
create function public.set_merchant_redeem_pin(p_merchant_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then
    raise exception 'El PIN debe tener 6 dígitos';
  end if;
  update public.partner_merchants
    set redeem_pin_hash = crypt(p_pin, gen_salt('bf')),
        redeem_pin_set_at = now()
    where id = p_merchant_id;
  if not found then
    raise exception 'Comercio no encontrado';
  end if;
end;
$$;

revoke execute on function public.set_merchant_redeem_pin(uuid, text) from public, anon, authenticated;
grant execute on function public.set_merchant_redeem_pin(uuid, text) to service_role;

-- Consulta (p_confirm = false) o entrega (p_confirm = true) de un canje.
-- Devuelve siempre jsonb { ok, error? | product, merchant, ... }.
-- Codigo inexistente y PIN incorrecto dan el MISMO error, para no revelar
-- que codigos existen.
create function public.merchant_redeem(
  p_code text,
  p_pin text,
  p_ip_hash text,
  p_confirm boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
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
    'merchant', v_merchant.name,
    'value_cents', v_redemption.points_cost,
    'expires_at', v_redemption.expires_at,
    'delivered_at', v_redemption.delivered_at
  );
end;
$$;

revoke execute on function public.merchant_redeem(text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.merchant_redeem(text, text, text, boolean) to service_role;

-- Limpieza: los intentos de mas de 30 dias no sirven para nada.
select cron.schedule(
  'cleanup-redeem-attempts',
  '30 8 * * *',
  $$ delete from public.redeem_attempts where created_at < now() - interval '30 days'; $$
);
