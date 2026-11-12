-- Al confirmarse una factura con la DGI, el gasto vinculado toma el valor
-- real de la factura (si era mayor o menor, o si se guardo sin monto porque
-- la DGI aun no la tenia publicada). Tambien ajusta el saldo de la cuenta
-- por la diferencia y, si el gasto quedo con el nombre generico
-- "Factura <RUC>", le pone el nombre del comercio.
-- No toca gastos separados por categoria (descripcion "Comercio · Categoria"):
-- esos ya se crearon con los montos de la propia factura.

create or replace function public.dgi_receipt_sync_expense()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t public.transactions%rowtype;
  v_target numeric;
  v_delta numeric;
  v_name text;
begin
  if new.status <> 'confirmada' or new.confirmed_amount is null or new.confirmed_amount <= 0
     or new.transaction_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'confirmada' and old.confirmed_amount is not distinct from new.confirmed_amount then
    return new;
  end if;

  select * into t from public.transactions where id = new.transaction_id and user_id = new.user_id for update;
  if not found or t.movement_type <> 'gasto' or coalesce(t.description, '') like '% · %' then
    return new;
  end if;

  v_target := -round(new.confirmed_amount, 2);
  v_delta := v_target - t.amount;
  v_name := case
    when new.merchant_name is not null and (t.description is null or t.description like 'Factura %')
      then replace(initcap(lower(new.merchant_name)), 'S.a.', 'S.A.')
    else t.description
  end;

  if v_delta <> 0 or v_name is distinct from t.description then
    update public.transactions set amount = v_target, description = v_name where id = t.id;
    if v_delta <> 0 then
      update public.accounts set balance = balance + v_delta where id = t.account_id and user_id = new.user_id;
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.dgi_receipt_sync_expense() from public, anon, authenticated;

drop trigger if exists dgi_receipt_sync_expense on public.dgi_receipts;
create trigger dgi_receipt_sync_expense
  after insert or update of status, confirmed_amount on public.dgi_receipts
  for each row execute function public.dgi_receipt_sync_expense();
