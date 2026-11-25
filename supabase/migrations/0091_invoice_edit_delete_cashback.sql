-- Movimientos con factura (transactions.invoice_cufe):
-- 1) Se pueden EDITAR la categoría, la descripción y las etiquetas. El
--    monto, el tipo, la fecha y la cuenta quedan como en la factura (el
--    monto no puede ser distinto al de la factura, así el cashback no
--    cambia al editar).
-- 2) Al ELIMINARLO se quita su cashback:
--    - si era la única parte (o la última) de la factura: se anulan los
--      créditos de esa factura (cashback y bono de tarjeta) y la factura
--      queda "anulada" (si estaba pendiente, ya no se acredita);
--    - si la factura se separó por categoría y se borra solo una parte: se
--      descuenta la parte proporcional del cashback ya acreditado.

alter table public.dgi_receipts drop constraint if exists dgi_receipts_status_check;
alter table public.dgi_receipts add constraint dgi_receipts_status_check
  check (status = any (array['pendiente','confirmada','rechazada','expirada','anulada']));

-- 1) Edición: solo categoría, descripción y etiquetas.
create or replace function public.transactions_lock_invoice()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if old.invoice_cufe is not null
     and coalesce(auth.role(), '') in ('authenticated', 'anon')
     and (new.amount, new.movement_type, new.occurred_at, new.account_id, new.invoice_cufe,
          new.original_currency, new.original_amount)
         is distinct from
         (old.amount, old.movement_type, old.occurred_at, old.account_id, old.invoice_cufe,
          old.original_currency, old.original_amount)
  then
    raise exception 'Este movimiento viene de una factura: el monto y la fecha deben ser los de la factura. Puedes cambiar la categoría y la descripción, o eliminarlo.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

-- 2) Eliminación: quitar el cashback.
create or replace function public.transactions_invoice_deleted()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ref text := 'factura:' || old.invoice_cufe;
  v_receipt public.dgi_receipts%rowtype;
  v_remaining int;
  v_awarded int;
  v_total numeric;
  v_cut int;
begin
  select * into v_receipt from public.dgi_receipts
   where cufe = old.invoice_cufe and user_id = old.user_id;
  if not found then return old; end if;

  select count(*) into v_remaining from public.transactions
   where user_id = old.user_id and invoice_cufe = old.invoice_cufe and id <> old.id;

  if v_remaining = 0 then
    -- Era la última parte: se anula todo lo de esa factura.
    update public.points_ledger set status = 'anulado',
           metadata = metadata || jsonb_build_object('anulado_por', 'movimiento_eliminado', 'anulado_at', now())
     where user_id = old.user_id
       and status in ('confirmado', 'pendiente')
       and (external_ref = v_ref or external_ref = v_ref || ':tarjeta' or external_ref like v_ref || ':parte:%');
    update public.dgi_receipts set status = 'anulada', updated_at = now()
     where id = v_receipt.id and status <> 'anulada';
  else
    -- Solo una parte de una factura separada por categoría: se descuenta
    -- la proporción del cashback ya acreditado.
    select coalesce(sum(points), 0) into v_awarded from public.points_ledger
     where user_id = old.user_id and status = 'confirmado' and points > 0
       and (external_ref = v_ref or external_ref = v_ref || ':tarjeta');
    v_total := coalesce(v_receipt.confirmed_amount, 0);
    if v_awarded > 0 and v_total > 0 then
      v_cut := least(v_awarded, round(v_awarded * abs(old.amount) / v_total)::int);
      if v_cut > 0 then
        insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
        values (old.user_id, 'ajuste', v_ref || ':parte:' || old.id, -v_cut, 'confirmado',
                jsonb_build_object('motivo', 'parte_de_factura_eliminada', 'cufe', old.invoice_cufe, 'monto', abs(old.amount)))
        on conflict (source, external_ref) do nothing;
      end if;
    end if;
  end if;
  return old;
end $$;
revoke execute on function public.transactions_invoice_deleted() from public, anon, authenticated;

drop trigger if exists transactions_invoice_deleted on public.transactions;
create trigger transactions_invoice_deleted
  after delete on public.transactions
  for each row when (old.invoice_cufe is not null)
  execute function public.transactions_invoice_deleted();
