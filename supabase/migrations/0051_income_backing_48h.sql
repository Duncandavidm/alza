-- Un ingreso respalda el cashback solo cuando ya tiene 48 horas registrado
-- en la app. Si la persona registra ingresos despues de escanear, el
-- cashback retenido se libera 48 h despues de registrar ese ingreso (sin
-- avisos). La liberacion corre cada hora.
create or replace function public.receipt_income_backed(p_receipt_id uuid)
returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $function$
  with r as (
    select id, user_id, confirmed_amount as amount, coalesce(authorized_at, scanned_at) as at
    from dgi_receipts where id = p_receipt_id
  ),
  income as (
    select coalesce(sum(t.amount), 0) as total
    from transactions t, r
    where t.user_id = r.user_id and t.movement_type = 'ingreso' and t.amount > 0
      and t.occurred_at >= r.at - interval '35 days' and t.occurred_at <= r.at + interval '3 days'
      and t.created_at <= now() - interval '48 hours'
  ),
  backed as (
    select coalesce(sum(o.confirmed_amount), 0) as total
    from dgi_receipts o, r
    where o.user_id = r.user_id and o.id <> r.id and o.cashback_status = 'acreditado'
      and coalesce(o.authorized_at, o.scanned_at) between r.at - interval '30 days' and r.at
  )
  select coalesce((select amount from r), 0) + (select total from backed) <= (select total from income)
$function$;

select cron.schedule('release-income-held-cashback', '23 * * * *', $$ select public.release_income_held_cashback(); $$);
