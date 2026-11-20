-- Cashback respaldado por ingresos.
--
-- Regla: el cashback de una factura solo se acredita si las compras con
-- cashback de los ultimos 30 dias (incluida esta) caben en los ingresos
-- que la persona registro en los ultimos 35 dias (+3 dias de gracia por
-- si anota el ingreso con fecha del dia de pago). Si no caben, el cashback
-- queda "pendiente" (se ve en la app como pendiente) hasta que registre
-- ingresos que lo respalden; si en 45 dias no los registra, se anula.
--
-- Se aplica con un trigger en points_ledger, asi vale para cualquier
-- camino que acredite cashback de facturas (job diario, bono de tarjeta).
-- Los asientos del ledger nunca se editan: liberar o anular es insertar
-- filas nuevas que compensan.

alter table public.dgi_receipts
  add column cashback_status text check (cashback_status in ('acreditado', 'sin_ingreso', 'vencido'));

create index dgi_receipts_user_cashback_idx on public.dgi_receipts (user_id, cashback_status);

-- ¿Los ingresos registrados respaldan esta factura?
create or replace function public.receipt_income_backed(p_receipt_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  with r as (
    select id, user_id, confirmed_amount as amount, coalesce(authorized_at, scanned_at) as at
    from dgi_receipts where id = p_receipt_id
  ),
  income as (
    select coalesce(sum(t.amount), 0) as total
    from transactions t, r
    where t.user_id = r.user_id and t.movement_type = 'ingreso' and t.amount > 0
      and t.occurred_at >= r.at - interval '35 days' and t.occurred_at <= r.at + interval '3 days'
  ),
  backed as (
    select coalesce(sum(o.confirmed_amount), 0) as total
    from dgi_receipts o, r
    where o.user_id = r.user_id and o.id <> r.id and o.cashback_status = 'acreditado'
      and coalesce(o.authorized_at, o.scanned_at) between r.at - interval '30 days' and r.at
  )
  select coalesce((select amount from r), 0) + (select total from backed) <= (select total from income)
$$;
revoke execute on function public.receipt_income_backed(uuid) from public, anon, authenticated;

create or replace function public.points_ledger_hold_unbacked_cashback()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_receipt public.dgi_receipts;
begin
  if new.status <> 'confirmado' or new.points <= 0
     or new.source not in ('factura', 'tarjeta')
     or new.external_ref not like 'factura:%' then
    return new;
  end if;

  select * into v_receipt from public.dgi_receipts
   where user_id = new.user_id and cufe = split_part(new.external_ref, ':', 2);
  if v_receipt.id is null then
    return new;
  end if;

  -- El bono de tarjeta (o la liberacion) sigue a la factura ya evaluada.
  if v_receipt.cashback_status = 'acreditado' then
    return new;
  end if;
  if v_receipt.cashback_status is null then
    if public.receipt_income_backed(v_receipt.id) then
      update public.dgi_receipts set cashback_status = 'acreditado' where id = v_receipt.id;
      return new;
    end if;
    update public.dgi_receipts set cashback_status = 'sin_ingreso' where id = v_receipt.id;
  end if;

  new.status := 'pendiente';
  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object('retenido', 'sin_ingreso');
  return new;
end $$;

create trigger points_ledger_hold_unbacked_cashback
  before insert on public.points_ledger
  for each row execute function public.points_ledger_hold_unbacked_cashback();

-- Job diario: libera el cashback retenido cuando ya hay ingresos que lo
-- respaldan (en orden de fecha), y anula el que lleva mas de 45 dias.
-- Devuelve por persona cuanto se libero (centavos), para el aviso push.
create or replace function public.release_income_held_cashback()
returns table (user_id uuid, released_cents integer, receipts integer)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_receipt record;
  v_row record;
begin
  create temp table if not exists _released (user_id uuid, cents integer) on commit drop;
  truncate _released;

  for v_receipt in
    select r.* from public.dgi_receipts r
    where r.cashback_status = 'sin_ingreso'
    order by coalesce(r.authorized_at, r.scanned_at)
  loop
    if coalesce(v_receipt.authorized_at, v_receipt.scanned_at) < now() - interval '45 days' then
      update public.dgi_receipts set cashback_status = 'vencido' where id = v_receipt.id;
      for v_row in
        select l.* from public.points_ledger l
        where l.user_id = v_receipt.user_id and l.status = 'pendiente'
          and l.external_ref in ('factura:' || v_receipt.cufe, 'factura:' || v_receipt.cufe || ':tarjeta')
      loop
        insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
        values (v_row.user_id, v_row.source, v_row.external_ref || ':vencido', -v_row.points, 'pendiente',
                jsonb_build_object('motivo', 'sin ingresos que respalden la compra en 45 dias'))
        on conflict (source, external_ref) do nothing;
      end loop;
      continue;
    end if;

    continue when not public.receipt_income_backed(v_receipt.id);

    update public.dgi_receipts set cashback_status = 'acreditado' where id = v_receipt.id;
    for v_row in
      select l.* from public.points_ledger l
      where l.user_id = v_receipt.user_id and l.status = 'pendiente'
        and l.external_ref in ('factura:' || v_receipt.cufe, 'factura:' || v_receipt.cufe || ':tarjeta')
    loop
      insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
      values (v_row.user_id, v_row.source, v_row.external_ref || ':liberado', -v_row.points, 'pendiente',
              jsonb_build_object('motivo', 'respaldado por ingresos'))
      on conflict (source, external_ref) do nothing;
      if found then
        insert into public.points_ledger (user_id, source, external_ref, points, status, occurred_at, metadata)
        values (v_row.user_id, v_row.source, v_row.external_ref || ':respaldado', v_row.points, 'confirmado',
                v_row.occurred_at, jsonb_build_object('motivo', 'respaldado por ingresos'))
        on conflict (source, external_ref) do nothing;
        insert into _released values (v_row.user_id, v_row.points);
      end if;
    end loop;
  end loop;

  return query
    select x.user_id, sum(x.cents)::integer, count(*)::integer from _released x group by x.user_id;
end $$;
revoke execute on function public.release_income_held_cashback() from public, anon, authenticated;

-- Las facturas que ya tenian cashback acreditado antes de esta regla
-- quedan como acreditadas (no se les quita nada).
update public.dgi_receipts r set cashback_status = 'acreditado'
where r.status = 'confirmada' and r.cashback_status is null
  and exists (select 1 from public.points_ledger l
              where l.user_id = r.user_id and l.external_ref = 'factura:' || r.cufe and l.status = 'confirmado');
