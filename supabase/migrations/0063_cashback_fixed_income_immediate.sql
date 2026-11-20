-- Cashback al momento si el ingreso es un pago fijo (1.0.2+).
-- Antes (0051) todo ingreso tenia que llevar 48 h registrado para respaldar
-- cashback. Ahora un ingreso recien anotado cuenta de una vez hasta el monto
-- de los ingresos fijos (recurring_transactions tipo 'ingreso', activos) que
-- la persona tiene registrados desde hace 48 h o mas. Lo que pase de ese
-- monto sigue esperando las 48 h. Asi el salario de cada mes libera el
-- cashback enseguida, pero no se puede inventar un ingreso grande para
-- cobrar al momento.
--
-- Tope por ingreso fijo dentro de la ventana (~38 dias): mensual 1 vez su
-- monto (quincenal son dos filas mensuales), semanal 5, diario 38.
create or replace function public.receipt_income_backed(p_receipt_id uuid)
returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $function$
  with r as (
    select id, user_id, confirmed_amount as amount, coalesce(authorized_at, scanned_at) as at
    from dgi_receipts where id = p_receipt_id
  ),
  window_income as (
    select t.amount, t.created_at
    from transactions t, r
    where t.user_id = r.user_id and t.movement_type = 'ingreso' and t.amount > 0
      and t.occurred_at >= r.at - interval '35 days' and t.occurred_at <= r.at + interval '3 days'
  ),
  mature as (
    select coalesce(sum(amount), 0) as total from window_income
    where created_at <= now() - interval '48 hours'
  ),
  fresh as (
    select coalesce(sum(amount), 0) as total from window_income
    where created_at > now() - interval '48 hours'
  ),
  fixed_cap as (
    select coalesce(sum(rt.amount * case rt.frequency when 'weekly' then 5 when 'daily' then 38 else 1 end), 0) as total
    from recurring_transactions rt, r
    where rt.user_id = r.user_id and rt.movement_type = 'ingreso' and rt.active
      and rt.amount > 0 and rt.created_at <= now() - interval '48 hours'
  ),
  backed as (
    select coalesce(sum(o.confirmed_amount), 0) as total
    from dgi_receipts o, r
    where o.user_id = r.user_id and o.id <> r.id and o.cashback_status = 'acreditado'
      and coalesce(o.authorized_at, o.scanned_at) between r.at - interval '30 days' and r.at
  )
  select coalesce((select amount from r), 0) + (select total from backed)
         <= (select total from mature) + least((select total from fresh), (select total from fixed_cap))
$function$;
