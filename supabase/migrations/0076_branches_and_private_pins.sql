-- 0076: sucursales de comercios aliados + PIN de caja privado.
--
-- Seguridad: partner_merchants.redeem_pin_hash se podia leer desde la app
-- (la politica de lectura es para cualquier usuario con sesion y el hash
-- bcrypt de un PIN de 6 digitos se puede romper por fuerza bruta). Los
-- hashes pasan a tablas sin acceso para anon/authenticated y la columna
-- se elimina. Las apps no la usan (sus modelos no la decodifican).
--
-- Sucursales: un comercio (un RUC) puede tener varias direcciones. La
-- direccion de la ficha es la principal; merchant_branches guarda las
-- demas, cada una con su "Como llegar" y, si se quiere, su propio PIN de
-- caja para saber en que sucursal se uso cada codigo.

-- ---------- PIN privado ----------
create table if not exists public.merchant_secrets (
  merchant_id uuid primary key references public.partner_merchants(id) on delete cascade,
  redeem_pin_hash text not null,
  updated_at timestamptz not null default now()
);
alter table public.merchant_secrets enable row level security;
revoke all on public.merchant_secrets from anon, authenticated;

insert into public.merchant_secrets (merchant_id, redeem_pin_hash)
select id, redeem_pin_hash from public.partner_merchants where redeem_pin_hash is not null
on conflict (merchant_id) do update set redeem_pin_hash = excluded.redeem_pin_hash;

-- ---------- Sucursales ----------
create table if not exists public.merchant_branches (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.partner_merchants(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  address text check (address is null or char_length(address) <= 300),
  maps_url text check (maps_url is null or char_length(maps_url) <= 1000),
  status text not null default 'active' check (status in ('active', 'paused')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists merchant_branches_merchant_idx on public.merchant_branches (merchant_id, sort_order);
alter table public.merchant_branches enable row level security;
drop policy if exists merchant_branches_select_authenticated on public.merchant_branches;
create policy merchant_branches_select_authenticated on public.merchant_branches
  for select to authenticated
  using (status = 'active' and exists (
    select 1 from public.partner_merchants m where m.id = merchant_id and m.status = 'active'));
revoke insert, update, delete on public.merchant_branches from anon, authenticated;
grant select on public.merchant_branches to authenticated;

create table if not exists public.merchant_branch_secrets (
  branch_id uuid primary key references public.merchant_branches(id) on delete cascade,
  redeem_pin_hash text not null,
  updated_at timestamptz not null default now()
);
alter table public.merchant_branch_secrets enable row level security;
revoke all on public.merchant_branch_secrets from anon, authenticated;

alter table public.merchant_branches add column if not exists redeem_pin_set_at timestamptz;

-- En que sucursal se uso cada codigo (null = la principal o sin PIN de sucursal).
alter table public.reward_redemptions
  add column if not exists branch_id uuid references public.merchant_branches(id) on delete set null;

-- ---------- PIN: comprobacion ----------
-- Devuelve si el PIN es el del comercio ('principal'), el de una sucursal
-- activa (su id) o ninguno (null).
create or replace function public.redeem_pin_match(p_merchant_id uuid, p_pin text, out matched boolean, out branch_id uuid)
 language plpgsql stable security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_hash text;
begin
  matched := false;
  branch_id := null;
  if p_merchant_id is null or coalesce(p_pin, '') !~ '^[0-9]{6}$' then
    return;
  end if;
  select s.redeem_pin_hash into v_hash from public.merchant_secrets s where s.merchant_id = p_merchant_id;
  if v_hash is not null and v_hash = crypt(p_pin, v_hash) then
    matched := true;
    return;
  end if;
  select b.id into branch_id
    from public.merchant_branches b
    join public.merchant_branch_secrets bs on bs.branch_id = b.id
   where b.merchant_id = p_merchant_id and b.status = 'active'
     and bs.redeem_pin_hash = crypt(p_pin, bs.redeem_pin_hash)
   limit 1;
  matched := branch_id is not null;
end $function$;
revoke all on function public.redeem_pin_match(uuid, text) from public, anon, authenticated;

create or replace function public.set_merchant_redeem_pin(p_merchant_id uuid, p_pin text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then
    raise exception 'El PIN debe tener 6 dígitos';
  end if;
  update public.partner_merchants set redeem_pin_set_at = now() where id = p_merchant_id;
  if not found then
    raise exception 'Comercio no encontrado';
  end if;
  insert into public.merchant_secrets (merchant_id, redeem_pin_hash, updated_at)
  values (p_merchant_id, crypt(p_pin, gen_salt('bf')), now())
  on conflict (merchant_id) do update set redeem_pin_hash = excluded.redeem_pin_hash, updated_at = now();
end;
$function$;
revoke execute on function public.set_merchant_redeem_pin(uuid, text) from public, anon, authenticated;
grant execute on function public.set_merchant_redeem_pin(uuid, text) to service_role;

create or replace function public.set_branch_redeem_pin(p_branch_id uuid, p_pin text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then
    raise exception 'El PIN debe tener 6 dígitos';
  end if;
  update public.merchant_branches set redeem_pin_set_at = now(), updated_at = now() where id = p_branch_id;
  if not found then
    raise exception 'Sucursal no encontrada';
  end if;
  insert into public.merchant_branch_secrets (branch_id, redeem_pin_hash, updated_at)
  values (p_branch_id, crypt(p_pin, gen_salt('bf')), now())
  on conflict (branch_id) do update set redeem_pin_hash = excluded.redeem_pin_hash, updated_at = now();
end;
$function$;
revoke execute on function public.set_branch_redeem_pin(uuid, text) from public, anon, authenticated;
grant execute on function public.set_branch_redeem_pin(uuid, text) to service_role;

-- ---------- Caja: login, canje con PIN y canje con turno ----------
create or replace function public.merchant_login(p_ruc text, p_pin text, p_ip_hash text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_merchant public.partner_merchants;
  v_failures integer;
  v_match record;
begin
  select count(*) into v_failures from public.redeem_attempts
   where ip_hash = coalesce(p_ip_hash, 'desconocida') and not success and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_merchant from public.partner_merchants
   where upper(regexp_replace(ruc, '\s', '', 'g')) = upper(regexp_replace(coalesce(p_ruc, ''), '\s', '', 'g'))
     and status = 'active';

  select * into v_match from public.redeem_pin_match(v_merchant.id, p_pin);
  if v_merchant.id is null or not coalesce(v_match.matched, false) then
    insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), 'LOGIN', false);
    return jsonb_build_object('ok', false, 'error', 'RUC o PIN incorrecto.');
  end if;

  insert into public.redeem_attempts (ip_hash, code, success) values (coalesce(p_ip_hash, 'desconocida'), 'LOGIN', true);
  return jsonb_build_object('ok', true, 'merchant_id', v_merchant.id, 'merchant', v_merchant.name,
    'branch_id', v_match.branch_id,
    'branch', (select b.name from public.merchant_branches b where b.id = v_match.branch_id));
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
  v_match record;
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
  select * into v_match from public.redeem_pin_match(v_merchant.id, p_pin);

  if v_redemption.id is null or not coalesce(v_match.matched, false) then
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
    return jsonb_build_object('ok', false, 'error', case when v_redemption.source = 'beneficio' and v_redemption.status <> 'cancelado' then 'Este código de descuento ya venció (dura 15 minutos). Pídele al cliente que genere uno nuevo en la app.' else 'Este código está vencido o fue cancelado.' end, 'product', v_item.name);
  end if;

  if p_confirm then
    update public.reward_redemptions
      set status = 'entregado', delivered_at = now(), delivered_via = 'comercio', branch_id = v_match.branch_id
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
    'reward_type', v_item.reward_type, 'is_benefit', v_redemption.source = 'beneficio',
    'discount_value', v_item.discount_value,
    'merchant', v_merchant.name, 'merchant_id', v_merchant.id, 'is_gift', v_redemption.source = 'regalo',
    'branch_id', v_match.branch_id,
    'branch', (select b.name from public.merchant_branches b where b.id = v_match.branch_id),
    'currency', v_redemption.currency,
    'value', v_redemption.points_cost,
    'value_cents', v_redemption.points_cost,
    'expires_at', v_redemption.expires_at,
    'delivered_at', v_redemption.delivered_at
  );
end;
$function$;

drop function if exists public.merchant_redeem_session(text, uuid, text, boolean);
create or replace function public.merchant_redeem_session(p_code text, p_merchant_id uuid, p_ip_hash text,
    p_confirm boolean default false, p_branch_id uuid default null)
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
  v_branch uuid;
begin
  select count(*) into v_failures from public.redeem_attempts
   where ip_hash = coalesce(p_ip_hash, 'desconocida') and not success and created_at > now() - interval '15 minutes';
  if v_failures >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera 15 minutos e intenta de nuevo.');
  end if;

  select * into v_merchant from public.partner_merchants where id = p_merchant_id;
  -- La sucursal del turno solo cuenta si es de este comercio.
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
    'expires_at', v_redemption.expires_at, 'delivered_at', v_redemption.delivered_at);
end $function$;
revoke execute on function public.merchant_redeem_session(text, uuid, text, boolean, uuid) from public, anon, authenticated;
grant execute on function public.merchant_redeem_session(text, uuid, text, boolean, uuid) to service_role;

-- Descuentos (my_benefits) con las sucursales del comercio.
create or replace function public.my_benefits()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
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
  where auth.uid() is not null and ri.free_benefit and ri.status = 'active' and pm.status = 'active';
$function$;

-- Ya no hace falta: el hash vive en merchant_secrets.
alter table public.partner_merchants drop column if exists redeem_pin_hash;
