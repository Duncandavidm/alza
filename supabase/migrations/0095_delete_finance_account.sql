-- 1.0.8: eliminar una cuenta (banco, efectivo, tarjeta...) desde la app.
--
-- Al borrar una cuenta, la base borra en cascada sus movimientos, pagos
-- fijos y cuentas por pagar. Para no perder el historial, la persona puede
-- pasarlos antes a otra de sus cuentas: se mueven tal cual, sin cambiar el
-- saldo de la cuenta que los recibe (son historia, el dinero ya se contó).
-- Siempre debe quedar al menos una cuenta.

-- Los movimientos con factura no dejan cambiar la cuenta (0091), salvo en
-- este traslado, que marca monavi.moving_account durante la transacción.
create or replace function public.transactions_lock_invoice()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if coalesce(current_setting('monavi.moving_account', true), '') = 'on'
     and (new.amount, new.movement_type, new.occurred_at, new.invoice_cufe, new.original_currency, new.original_amount)
         is not distinct from
         (old.amount, old.movement_type, old.occurred_at, old.invoice_cufe, old.original_currency, old.original_amount)
  then
    return new;
  end if;
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

create or replace function public.delete_finance_account(p_account_id uuid, p_move_to uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_moved int := 0;
  v_count int;
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if not exists (select 1 from public.accounts where id = p_account_id and user_id = v_uid) then
    raise exception 'Cuenta no encontrada' using errcode = 'P0001';
  end if;
  select count(*) into v_count from public.accounts where user_id = v_uid;
  if v_count <= 1 then
    raise exception 'Necesitas al menos una cuenta en MonAvi.' using errcode = 'P0001';
  end if;

  if p_move_to is not null then
    if p_move_to = p_account_id
       or not exists (select 1 from public.accounts where id = p_move_to and user_id = v_uid) then
      raise exception 'La cuenta de destino no es válida.' using errcode = 'P0001';
    end if;
    perform set_config('monavi.moving_account', 'on', true);
    update public.transactions set account_id = p_move_to
     where account_id = p_account_id and user_id = v_uid;
    get diagnostics v_moved = row_count;
    update public.recurring_transactions set account_id = p_move_to
     where account_id = p_account_id and user_id = v_uid;
    update public.bills set account_id = p_move_to
     where account_id = p_account_id and user_id = v_uid;
    perform set_config('monavi.moving_account', 'off', true);
  end if;

  delete from public.accounts where id = p_account_id and user_id = v_uid;
  return jsonb_build_object('moved', v_moved);
end $$;

revoke all on function public.delete_finance_account(uuid, uuid) from public, anon;
grant execute on function public.delete_finance_account(uuid, uuid) to authenticated;
