-- Descuentos de aliados "por ser de MonAvi" (app 1.0.3), su reporte de
-- visitas, avisos de aliados nuevos y de pedir la factura, y un freno a
-- las consultas a la DGI.
--
-- 1) Descuento gratis (reward_items.free_benefit): no cuesta cashback. Se
--    desbloquea con la primera factura escaneada, pide correo verificado y
--    tiene limite por persona (por defecto 1 por semana; el comercio lo
--    cambia). Al usarlo se genera un codigo de un solo uso que dura 15
--    minutos (source 'beneficio'). Las apps viejas no los ven (RLS) ni
--    pueden canjearlos, y no disparan el aviso de "ya te alcanza".
-- 2) merchant_benefit_report: usos, facturas que trajo cada uso (misma
--    persona, mismo RUC, cerca de la hora del uso), ticket promedio,
--    ventas y clientes nuevos.
-- 3) Avisos: comercio aliado nuevo (una vez, a quien acepto 'ofertas') y
--    "escanea tu factura" una hora despues de usar un descuento.
-- 4) DGI: tope global de consultas por minuto y pausa automatica si la
--    DGI empieza a fallar o a responder algo que no es su pagina.

-- ---------------------------------------------------------------------
-- 1) Descuentos gratis
-- ---------------------------------------------------------------------

alter table public.reward_items
  add column if not exists free_benefit boolean not null default false,
  add column if not exists per_user_limit integer,
  add column if not exists per_user_period text;

alter table public.reward_items drop constraint if exists reward_items_points_cost_check;
alter table public.reward_items
  add constraint reward_items_points_cost_check check (
    (free_benefit and points_cost = 0) or (not free_benefit and points_cost > 0)
  );

alter table public.reward_items drop constraint if exists reward_items_benefit_limit_check;
alter table public.reward_items
  add constraint reward_items_benefit_limit_check check (
    (not free_benefit and per_user_limit is null and per_user_period is null)
    or (free_benefit and per_user_limit between 1 and 100
        and per_user_period in ('dia', 'semana', 'mes', 'siempre'))
  );

alter table public.reward_redemptions drop constraint if exists reward_redemptions_source_check;
alter table public.reward_redemptions
  add constraint reward_redemptions_source_check check (source in ('canje', 'regalo', 'beneficio'));

alter table public.reward_redemptions drop constraint if exists reward_redemptions_points_cost_check;
alter table public.reward_redemptions
  add constraint reward_redemptions_points_cost_check check (
    points_cost > 0 or (points_cost = 0 and source in ('beneficio', 'regalo'))
  );

alter table public.reward_redemptions
  add column if not exists invoice_reminder_sent_at timestamptz;

create index if not exists reward_redemptions_benefit_idx
  on public.reward_redemptions (user_id, reward_item_id, delivered_at)
  where source = 'beneficio';

-- Las apps hasta 1.0.2 leen reward_items directo: los descuentos gratis no
-- les llegan (no sabrian usarlos). La 1.0.3 los pide con my_benefits().
drop policy if exists reward_items_select_active on public.reward_items;
create policy reward_items_select_active on public.reward_items
  for select using (
    status = 'active' and not free_benefit
    and exists (select 1 from public.partner_merchants m where m.id = reward_items.merchant_id and m.status = 'active')
  );

-- Cupo: un codigo emitido cuenta mientras no venza (los de 15 minutos se
-- liberan solos al vencer).
create or replace function public.reward_item_used(p_item_id uuid)
returns integer
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select count(*)::int from public.reward_redemptions
  where reward_item_id = p_item_id
    and source <> 'regalo'
    and (status = 'entregado' or (status = 'emitido' and expires_at > now()));
$$;
revoke all on function public.reward_item_used(uuid) from public, anon, authenticated;

-- Un descuento vencido o cancelado no devuelve nada (no costo nada).
create or replace function public.release_redemption(p_redemption_id uuid, p_status text)
 returns reward_redemptions
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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

  if v_row.source in ('regalo', 'beneficio') or v_row.points_cost = 0 then
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
end $function$;

-- Los codigos de descuento duran 15 minutos: se vencen cada 10 minutos en
-- vez de una vez al dia (asi tambien se libera el cupo).
select cron.alter_job(
  job_id := (select jobid from cron.job where jobname = 'expire-reward-redemptions'),
  schedule := '*/10 * * * *'
);

-- Un premio con costo 0 siempre "alcanza": los descuentos no van en el
-- aviso de "ya te alcanza para un premio".
create or replace function public.reward_unlocks_to_notify()
 returns table(user_id uuid, items jsonb)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
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
    select u.user_id, ri.id as item_id, ri.name, pm.name as merchant, ri.points_cost, pm.reward_currency
    from users_with_tokens u
    cross join public.reward_items ri
    join public.partner_merchants pm on pm.id = ri.merchant_id
    where ri.status = 'active' and pm.status = 'active' and not ri.free_benefit
      and public.reward_balance(u.user_id, pm.reward_currency) >= ri.points_cost
      and not exists (
        select 1 from public.reward_unlock_notifications n
        where n.user_id = u.user_id and n.reward_item_id = ri.id
      )
  )
  select a.user_id,
         jsonb_agg(jsonb_build_object(
           'id', a.item_id, 'name', a.name, 'merchant', a.merchant,
           'cost', a.points_cost, 'currency', a.reward_currency
         ) order by a.points_cost desc)
  from affordable a
  group by a.user_id;
end;
$function$;

-- Desbloqueo: al menos una factura escaneada que no fue rechazada.
create or replace function public.has_scanned_receipt(p_user_id uuid)
returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select exists (
    select 1 from public.dgi_receipts r
    where r.user_id = p_user_id and r.status in ('pendiente', 'confirmada')
  );
$$;
revoke all on function public.has_scanned_receipt(uuid) from public, anon, authenticated;

-- Inicio y fin del periodo del limite, en hora de Panama ("semana" =
-- lunes a domingo).
create or replace function public.benefit_period_start(p_period text, p_at timestamptz default now())
returns timestamptz
language sql stable set search_path to 'public', 'pg_temp' as $$
  select case p_period
    when 'dia' then date_trunc('day', p_at at time zone 'America/Panama') at time zone 'America/Panama'
    when 'semana' then date_trunc('week', p_at at time zone 'America/Panama') at time zone 'America/Panama'
    when 'mes' then date_trunc('month', p_at at time zone 'America/Panama') at time zone 'America/Panama'
    else '-infinity'::timestamptz
  end;
$$;

create or replace function public.benefit_period_end(p_period text, p_at timestamptz default now())
returns timestamptz
language sql stable set search_path to 'public', 'pg_temp' as $$
  select case p_period
    when 'dia' then (date_trunc('day', p_at at time zone 'America/Panama') + interval '1 day') at time zone 'America/Panama'
    when 'semana' then (date_trunc('week', p_at at time zone 'America/Panama') + interval '1 week') at time zone 'America/Panama'
    when 'mes' then (date_trunc('month', p_at at time zone 'America/Panama') + interval '1 month') at time zone 'America/Panama'
    else null
  end;
$$;

create or replace function public.benefit_uses_in_period(p_user_id uuid, p_item public.reward_items)
returns integer
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select count(*)::int from public.reward_redemptions rr
  where rr.user_id = p_user_id and rr.reward_item_id = p_item.id
    and rr.source = 'beneficio' and rr.status = 'entregado'
    and rr.delivered_at >= public.benefit_period_start(p_item.per_user_period);
$$;
revoke all on function public.benefit_uses_in_period(uuid, public.reward_items) from public, anon, authenticated;

-- Genera (o devuelve el que ya tiene vigente) el codigo de un descuento.
create or replace function public.use_benefit(p_item_id uuid)
returns public.reward_redemptions
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
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
  select * into v_merchant from public.partner_merchants where id = v_item.merchant_id;
  if v_merchant.id is null or v_merchant.status <> 'active' then
    raise exception 'Este comercio ya no está disponible' using errcode = 'P0001';
  end if;

  if not public.has_scanned_receipt(v_user) then
    raise exception 'Escanea tu primera factura fiscal para desbloquear los descuentos' using errcode = 'P0001';
  end if;

  -- Si ya tiene un codigo vigente de este descuento, se le muestra el mismo.
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
end $$;
revoke all on function public.use_benefit(uuid) from public, anon;
grant execute on function public.use_benefit(uuid) to authenticated;

-- Descuentos para la app: cada uno con su comercio, cuantas veces ya lo
-- uso en el periodo, cuando vuelve a estar disponible y su codigo vigente.
create or replace function public.my_benefits()
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'unlocked', coalesce(public.has_scanned_receipt(auth.uid()), false),
    'benefits', coalesce(jsonb_agg(jsonb_build_object(
        'item', to_jsonb(ri) || jsonb_build_object(
          'partner_merchants', to_jsonb(pm) - 'redeem_pin_hash' - 'redeem_pin_set_at' - 'announced_at'),
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
$$;
revoke all on function public.my_benefits() from public, anon;
grant execute on function public.my_benefits() to authenticated;

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
    return jsonb_build_object('ok', false, 'error', case when v_redemption.source = 'beneficio' and v_redemption.status <> 'cancelado' then 'Este código de descuento ya venció (dura 15 minutos). Pídele al cliente que genere uno nuevo en la app.' else 'Este código está vencido o fue cancelado.' end, 'product', v_item.name);
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
    'reward_type', v_item.reward_type, 'is_benefit', v_redemption.source = 'beneficio', 'discount_value', v_item.discount_value,
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
    return jsonb_build_object('ok', false, 'error', case when v_redemption.source = 'beneficio' and v_redemption.status <> 'cancelado' then 'Este código de descuento ya venció (dura 15 minutos). Pídele al cliente que genere uno nuevo en la app.' else 'Este código está vencido o fue cancelado.' end, 'product', v_item.name);
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
    'reward_type', v_item.reward_type, 'is_benefit', v_redemption.source = 'beneficio',
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

-- ---------------------------------------------------------------------
-- 2) Reporte de visitas por descuento (solo panel: service role)
-- ---------------------------------------------------------------------
-- Cada uso entregado en caja es una visita. Se le atribuye la factura de
-- esa misma persona en ese mismo RUC emitida entre 3 h antes y 12 h despues
-- del uso (la mas cercana). Monto: el confirmado por la DGI o, si aun esta
-- pendiente, el del gasto registrado. "Cliente nuevo": no tenia facturas
-- en ese comercio antes de su primer uso.
create or replace function public.merchant_benefit_report(p_merchant_id uuid, p_days integer default 90)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
with m as (
  select id, ruc from public.partner_merchants where id = p_merchant_id
),
uses as (
  select rr.id, rr.user_id, rr.reward_item_id, rr.delivered_at
  from public.reward_redemptions rr, m
  where rr.merchant_id = m.id and rr.source = 'beneficio' and rr.status = 'entregado'
    and rr.delivered_at >= now() - make_interval(days => greatest(p_days, 1))
),
matched as (
  select u.*, rec.amount
  from uses u
  cross join m
  left join lateral (
    select coalesce(r.confirmed_amount, abs(t.amount)) as amount
    from public.dgi_receipts r
    left join public.transactions t on t.id = r.transaction_id
    where r.user_id = u.user_id and r.ruc = m.ruc and r.status in ('pendiente', 'confirmada')
      and coalesce(r.authorized_at, r.scanned_at) between u.delivered_at - interval '3 hours'
                                                      and u.delivered_at + interval '12 hours'
    order by abs(extract(epoch from coalesce(r.authorized_at, r.scanned_at) - u.delivered_at))
    limit 1
  ) rec on true
),
first_use as (
  select user_id, min(delivered_at) as first_at from uses group by user_id
),
newcomers as (
  select f.user_id
  from first_use f, m
  where not exists (
    select 1 from public.dgi_receipts r
    where r.user_id = f.user_id and r.ruc = m.ruc
      and coalesce(r.authorized_at, r.scanned_at) < f.first_at - interval '3 hours')
)
select jsonb_build_object(
  'days', p_days,
  'uses', (select count(*) from matched),
  'customers', (select count(distinct user_id) from matched),
  'new_customers', (select count(*) from newcomers),
  'with_receipt', (select count(*) from matched where amount is not null),
  'receipt_rate', (select round(100.0 * count(*) filter (where amount is not null) / nullif(count(*), 0), 1) from matched),
  'avg_ticket', (select round(avg(amount), 2) from matched),
  'total_sales', (select coalesce(round(sum(amount), 2), 0) from matched),
  'by_item', coalesce((
    select jsonb_agg(row_to_json(x) order by x.uses desc)
    from (
      select ri.name, count(*) as uses, count(distinct mt.user_id) as customers,
             count(mt.amount) as with_receipt, round(avg(mt.amount), 2) as avg_ticket,
             coalesce(round(sum(mt.amount), 2), 0) as total_sales
      from matched mt join public.reward_items ri on ri.id = mt.reward_item_id
      group by ri.name
    ) x), '[]'::jsonb),
  'by_week', coalesce((
    select jsonb_agg(row_to_json(x) order by x.week)
    from (
      select to_char(date_trunc('week', delivered_at at time zone 'America/Panama'), 'YYYY-MM-DD') as week,
             count(*) as uses, round(avg(amount), 2) as avg_ticket
      from matched group by 1
    ) x), '[]'::jsonb)
);
$$;
revoke all on function public.merchant_benefit_report(uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) Avisos
-- ---------------------------------------------------------------------

-- Comercio aliado nuevo: se anuncia una vez, cuando ya tiene algo activo.
alter table public.partner_merchants add column if not exists announced_at timestamptz;
update public.partner_merchants set announced_at = now() where announced_at is null;

create or replace function public.partner_announcements_pending()
returns table(merchant_id uuid, name text, benefit text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select pm.id, pm.name,
         (select ri.name from public.reward_items ri
           where ri.merchant_id = pm.id and ri.status = 'active' and ri.free_benefit
           order by ri.sort_order, ri.created_at limit 1)
  from public.partner_merchants pm
  where pm.status = 'active' and pm.announced_at is null
    and exists (select 1 from public.reward_items ri where ri.merchant_id = pm.id and ri.status = 'active');
$$;
revoke all on function public.partner_announcements_pending() from public, anon, authenticated;

-- "Escanea tu factura": entre 1 y 24 h despues de usar un descuento, si
-- esa persona no ha escaneado una factura de ese comercio desde el uso.
create or replace function public.benefit_invoice_reminders_pending()
returns table(redemption_id uuid, user_id uuid, merchant text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select rr.id, rr.user_id, pm.name
  from public.reward_redemptions rr
  join public.partner_merchants pm on pm.id = rr.merchant_id
  where rr.source = 'beneficio' and rr.status = 'entregado' and rr.invoice_reminder_sent_at is null
    and rr.delivered_at between now() - interval '24 hours' and now() - interval '1 hour'
    and not exists (
      select 1 from public.dgi_receipts r
      where r.user_id = rr.user_id and r.ruc = pm.ruc and r.scanned_at >= rr.delivered_at - interval '3 hours');
$$;
revoke all on function public.benefit_invoice_reminders_pending() from public, anon, authenticated;

-- Cada hora: solo los recordatorios de factura (award-habit-points en
-- modo "hourly"). La corrida diaria hace todo lo demas.
select cron.schedule(
  'benefit-invoice-reminders',
  '37 * * * *',
  $cron$
  select net.http_post(
    url := 'https://jfhevxztsvnlsuwkwtmd.supabase.co/functions/v1/award-habit-points',
    headers := jsonb_build_object('Content-Type','application/json',
      'x-admin-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret')),
    body := '{"mode":"hourly"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);

-- ---------------------------------------------------------------------
-- 4) Freno a las consultas a la DGI
-- ---------------------------------------------------------------------
-- Todas las consultas (al escanear y la verificacion de cada hora) piden
-- permiso a dgi_acquire(): si en el ultimo minuto ya van
-- dgi_max_requests_per_minute (30 por defecto) o la DGI esta en pausa, no
-- se consulta y la factura queda pendiente para la proxima corrida. Cada
-- respuesta se reporta con dgi_report(): si las ultimas 8 de los ultimos
-- 15 minutos fallaron (caida, bloqueo o una pagina que no es la de la
-- DGI), se pausa 30 min, y si vuelve a pasar en 24 h, el doble (hasta 6 h).
create table if not exists public.dgi_request_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  source text not null,
  outcome text check (outcome in ('ok', 'not_found', 'blocked', 'error', 'cache'))
);
create index if not exists dgi_request_log_at_idx on public.dgi_request_log (at);
alter table public.dgi_request_log enable row level security;

create table if not exists public.dgi_guard (
  id integer primary key default 1 check (id = 1),
  paused_until timestamptz,
  trips integer not null default 0,
  last_trip_at timestamptz,
  updated_at timestamptz not null default now()
);
insert into public.dgi_guard (id) values (1) on conflict do nothing;
alter table public.dgi_guard enable row level security;

-- Pagina de la DGI ya leida al escanear: la verificacion inmediata la usa
-- en vez de volver a consultar (se borra al usarla o a la hora).
create table if not exists public.dgi_page_cache (
  cufe text primary key,
  html text not null,
  fetched_at timestamptz not null default now()
);
alter table public.dgi_page_cache enable row level security;

create or replace function public.dgi_acquire(p_source text)
returns bigint
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_limit integer := coalesce((select (value #>> '{}')::int from public.app_config where key = 'dgi_max_requests_per_minute'), 30);
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('dgi_acquire'));
  if exists (select 1 from public.dgi_guard where id = 1 and paused_until > now()) then
    return null;
  end if;
  if (select count(*) from public.dgi_request_log where at > now() - interval '1 minute' and outcome is distinct from 'cache') >= v_limit then
    return null;
  end if;
  insert into public.dgi_request_log (source) values (left(coalesce(p_source, '?'), 40)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.dgi_acquire(text) from public, anon, authenticated;

create or replace function public.dgi_report(p_id bigint, p_outcome text)
returns void
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_failures integer;
  v_total integer;
  v_guard public.dgi_guard;
  v_trips integer;
begin
  update public.dgi_request_log set outcome = p_outcome where id = p_id;
  if p_outcome not in ('blocked', 'error') then return; end if;

  select count(*) filter (where outcome in ('blocked', 'error')), count(*)
    into v_failures, v_total
  from (
    select outcome from public.dgi_request_log
    where at > now() - interval '15 minutes' and outcome in ('ok', 'not_found', 'blocked', 'error')
    order by at desc limit 8
  ) last8;
  if v_total < 8 or v_failures < 8 then return; end if;

  select * into v_guard from public.dgi_guard where id = 1 for update;
  if v_guard.paused_until > now() then return; end if;
  v_trips := case when v_guard.last_trip_at > now() - interval '24 hours' then v_guard.trips + 1 else 1 end;
  update public.dgi_guard
     set trips = v_trips, last_trip_at = now(), updated_at = now(),
         paused_until = now() + least(interval '30 minutes' * power(2, v_trips - 1), interval '6 hours')
   where id = 1;
end $$;
revoke all on function public.dgi_report(bigint, text) from public, anon, authenticated;

select cron.schedule(
  'cleanup-dgi-request-log',
  '47 * * * *',
  $cron$ delete from public.dgi_request_log where at < now() - interval '14 days';
         delete from public.dgi_page_cache where fetched_at < now() - interval '1 hour'; $cron$
);
