-- Dos monedas de premio:
--   * CASHBACK (centavos de US$): facturas DGI verificadas (1%).
--     Fuentes del ledger: factura, tarjeta, ajuste, canje.
--   * PUNTOS: buenos habitos y metas de ahorro, calculados en el SERVIDOR
--     (award_habit_points) con las mismas reglas anti-trampa que la app
--     (constancia, aportes que maduran 30 dias y caben en ingresos -
--     gastos, presupuestos cumplidos solo si se anoto, tope 400/mes).
--     Fuentes: habito, canje_puntos.
-- Cada comercio decide en que moneda canjea sus premios.

alter table public.points_ledger drop constraint points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check
  check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje', 'canje_puntos'));

alter table public.partner_merchants
  add column reward_currency text not null default 'cashback'
    check (reward_currency in ('cashback', 'puntos'));

alter table public.reward_redemptions
  add column currency text not null default 'cashback'
    check (currency in ('cashback', 'puntos'));

-- (La fuente 'ahorro' era el programa con bancos, ya retirado: no
-- cuenta en ningun saldo.)
-- Saldos por usuario. confirmed_points / pending_points se mantienen
-- (= cashback en centavos) para no romper versiones de la app ya
-- instaladas; habit_points es el saldo de puntos canjeable y
-- habit_points_earned el total historico (para el nivel).
create or replace view public.points_balances
  with (security_invoker = true)
  as
  select
    user_id,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('factura', 'tarjeta', 'ajuste', 'canje')), 0) as confirmed_points,
    coalesce(sum(points) filter (where status = 'pendiente' and source in ('factura', 'tarjeta', 'ajuste', 'canje')), 0) as pending_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source in ('habito', 'canje_puntos')), 0) as habit_points,
    coalesce(sum(points) filter (where status = 'confirmado' and source = 'habito' and points > 0), 0) as habit_points_earned
  from public.points_ledger
  group by user_id;

-- Saldo de una moneda para un usuario.
create function public.reward_balance(p_user_id uuid, p_currency text)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(points), 0)::integer
  from public.points_ledger
  where user_id = p_user_id
    and status = 'confirmado'
    and source = any (
      case when p_currency = 'puntos'
        then array['habito', 'canje_puntos']
        else array['factura', 'tarjeta', 'ajuste', 'canje']
      end
    );
$$;

revoke execute on function public.reward_balance(uuid, text) from public, anon, authenticated;

create or replace function public.redeem_reward(p_item_id uuid)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));

  select * into v_item from public.reward_items where id = p_item_id;
  if v_item.id is null or v_item.status <> 'active' then
    raise exception 'Este producto ya no está disponible' using errcode = 'P0001';
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
$$;

create or replace function public.release_redemption(p_redemption_id uuid, p_status text)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
end;
$$;

-- ---------------------------------------------------------------------------
-- Puntos por habitos, calculados en el servidor (idempotente: cada logro
-- tiene un external_ref unico; volver a correrlo no duplica nada).
-- ---------------------------------------------------------------------------
create function public.award_habit_points(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cap constant integer := 400;
  v_inserted integer;
begin
  with
  -- Dias anotados: por la hora en que se ANOTO (created_at), no por la
  -- fecha que el usuario le pone al movimiento.
  logged_days as (
    select distinct t.user_id, (t.created_at at time zone 'America/Panama')::date as day
    from public.transactions t
    where t.created_at <= p_now
  ),
  day_events as (
    select user_id, 'habito:dia:' || day as ref, 5 as points,
           (day::timestamp at time zone 'America/Panama') as occurred_at
    from logged_days
  ),
  -- Sobrante registrado por mes (ingresos - gastos), para respaldar ahorro.
  surplus as (
    select t.user_id,
           date_trunc('month', t.occurred_at at time zone 'America/Panama') as month,
           sum(case when t.movement_type = 'ingreso' then abs(t.amount)
                    when t.movement_type in ('gasto', 'pago_proveedor') then -abs(t.amount)
                    else 0 end) as amount
    from public.transactions t
    group by 1, 2
  ),
  positives as (
    select c.*,
           date_trunc('month', c.created_at at time zone 'America/Panama') as month,
           sum(c.amount) over (
             partition by c.user_id, date_trunc('month', c.created_at at time zone 'America/Panama')
             order by c.created_at, c.id
           ) as running
    from public.savings_contributions c
    where c.amount > 0
  ),
  matured as (
    select p.user_id, p.created_at, p.created_at + interval '30 days' as matures_at
    from positives p
    left join surplus s on s.user_id = p.user_id and s.month = p.month
    where p.running <= greatest(coalesce(s.amount, 0), 0)
      and p.created_at + interval '30 days' <= p_now
      and not exists (
        select 1 from public.savings_contributions w
        where w.goal_id = p.goal_id
          and w.amount < 0
          and w.created_at > p.created_at
          and w.created_at <= p.created_at + interval '30 days'
      )
  ),
  savings_events as (
    select user_id,
           'habito:ahorro:' || (date_trunc('week', created_at at time zone 'America/Panama'))::date as ref,
           25 as points,
           min(matures_at) as occurred_at
    from matured
    group by user_id, date_trunc('week', created_at at time zone 'America/Panama')
  ),
  -- Presupuestos: periodos completos ya cerrados desde que existe el
  -- presupuesto, con el usuario anotando de verdad en ese periodo.
  budget_periods as (
    select b.id as budget_id, b.user_id, b.category, b.limit_amount, b.period,
           gs as period_start,
           gs + case when b.period = 'monthly' then interval '1 month' else interval '1 week' end as period_end
    from public.budgets b,
    lateral generate_series(
      date_trunc(case when b.period = 'monthly' then 'month' else 'week' end,
                 b.created_at at time zone 'America/Panama')
        + case when b.period = 'monthly' then interval '1 month' else interval '1 week' end,
      (p_now at time zone 'America/Panama'),
      case when b.period = 'monthly' then interval '1 month' else interval '1 week' end
    ) as gs
  ),
  budget_events as (
    select bp.user_id,
           'habito:presupuesto:' || bp.budget_id || ':' || bp.period_start::date as ref,
           case when bp.period = 'monthly' then 30 else 10 end as points,
           (bp.period_end at time zone 'America/Panama') as occurred_at
    from budget_periods bp
    where (bp.period_end at time zone 'America/Panama') <= p_now
      and (
        select count(*) from logged_days ld
        where ld.user_id = bp.user_id and ld.day >= bp.period_start::date and ld.day < bp.period_end::date
      ) >= case when bp.period = 'monthly' then 10 else 3 end
      and (
        select coalesce(sum(abs(t.amount)), 0) from public.transactions t
        where t.user_id = bp.user_id
          and t.movement_type in ('gasto', 'pago_proveedor')
          and t.category = bp.category
          and t.occurred_at >= (bp.period_start at time zone 'America/Panama')
          and t.occurred_at < (bp.period_end at time zone 'America/Panama')
      ) <= bp.limit_amount
  ),
  all_events as (
    select * from day_events
    union all select * from savings_events
    union all select * from budget_events
  ),
  capped as (
    select e.*,
           sum(points) over (
             partition by user_id, date_trunc('month', occurred_at at time zone 'America/Panama')
             order by occurred_at, ref
           ) as running
    from all_events e
  ),
  granted as (
    select user_id, ref, occurred_at,
           least(points, v_cap - (running - points)) as points
    from capped
    where running - points < v_cap
  ),
  inserted as (
    insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
    select user_id, 'habito', ref, points, 'confirmado', occurred_at, '{}'::jsonb
    from granted
    where points > 0
    on conflict (source, external_ref) do nothing
    returning 1
  )
  select count(*) into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke execute on function public.award_habit_points(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Aviso "ya te alcanza para un premio": se avisa UNA vez por premio; si el
-- saldo vuelve a bajar (p. ej. tras canjear) se olvida, y se avisa de
-- nuevo cuando vuelva a alcanzar.
-- ---------------------------------------------------------------------------
create table public.reward_unlock_notifications (
  user_id uuid not null references auth.users (id) on delete cascade,
  reward_item_id uuid not null references public.reward_items (id) on delete cascade,
  notified_at timestamptz not null default now(),
  primary key (user_id, reward_item_id)
);

alter table public.reward_unlock_notifications enable row level security;

create function public.reward_unlocks_to_notify()
returns table (user_id uuid, items jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  -- Olvidar los que ya no alcanzan.
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
    where ri.status = 'active' and pm.status = 'active'
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
$$;

revoke execute on function public.reward_unlocks_to_notify() from public, anon, authenticated;

create function public.mark_reward_unlocks_notified(p_user_id uuid, p_item_ids uuid[])
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.reward_unlock_notifications (user_id, reward_item_id)
  select p_user_id, unnest(p_item_ids)
  on conflict do nothing;
$$;

revoke execute on function public.mark_reward_unlocks_notified(uuid, uuid[]) from public, anon, authenticated;

-- merchant_redeem: devuelve la moneda para que /canjear muestre
-- "150 puntos" o "$1.50 de cashback".
create or replace function public.merchant_redeem(
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
    'currency', v_redemption.currency,
    'value', v_redemption.points_cost,
    'value_cents', v_redemption.points_cost,
    'expires_at', v_redemption.expires_at,
    'delivered_at', v_redemption.delivered_at
  );
end;
$$;
