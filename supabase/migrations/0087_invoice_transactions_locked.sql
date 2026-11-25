-- 1.0.6: un movimiento que viene de una factura leida (escaneada, en PDF o
-- unida con «¿Te dieron factura?») no se puede editar; si se puede eliminar.
--
-- transactions.invoice_cufe marca esos movimientos (tambien las partes de
-- una factura separada por categoria). Lo pone el servidor al registrarse la
-- factura, asi funciona igual con versiones viejas de la app.
--
-- El bloqueo es en la base de datos: un usuario (rol authenticated) no
-- puede cambiar un movimiento marcado. El servidor (service_role, p. ej. la
-- actualizacion del monto con el valor de la DGI de la 0052) si puede.

alter table public.transactions add column if not exists invoice_cufe text;

create index if not exists transactions_invoice_cufe_idx
  on public.transactions (invoice_cufe) where invoice_cufe is not null;

-- Marca el movimiento de la factura y, si la factura se separo por
-- categoria ("Comercio · Categoria"), las demas partes: misma persona,
-- cuenta y fecha, mismo comercio y creadas casi al mismo tiempo.
create or replace function public.mark_invoice_transactions(p_transaction_id uuid, p_user_id uuid, p_cufe text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  m public.transactions%rowtype;
begin
  select * into m from public.transactions where id = p_transaction_id and user_id = p_user_id;
  if not found then return; end if;

  update public.transactions set invoice_cufe = p_cufe
   where id = m.id and invoice_cufe is distinct from p_cufe;

  if coalesce(m.description, '') like '% · %' then
    update public.transactions s set invoice_cufe = p_cufe
     where s.user_id = m.user_id
       and s.account_id = m.account_id
       and s.occurred_at = m.occurred_at
       and s.id <> m.id
       and s.invoice_cufe is null
       and s.description like split_part(m.description, ' · ', 1) || ' · %'
       and abs(extract(epoch from s.created_at - m.created_at)) < 120;
  end if;
end $$;
revoke execute on function public.mark_invoice_transactions(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.dgi_receipt_mark_transactions()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.transaction_id is not null then
    perform public.mark_invoice_transactions(new.transaction_id, new.user_id, new.cufe);
  end if;
  return new;
end $$;
revoke execute on function public.dgi_receipt_mark_transactions() from public, anon, authenticated;

drop trigger if exists dgi_receipt_mark_transactions on public.dgi_receipts;
create trigger dgi_receipt_mark_transactions
  after insert or update of transaction_id on public.dgi_receipts
  for each row execute function public.dgi_receipt_mark_transactions();

-- Bloqueo de edicion.
create or replace function public.transactions_lock_invoice()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if old.invoice_cufe is not null
     and coalesce(auth.role(), '') in ('authenticated', 'anon')
     and (new.amount, new.movement_type, new.category, new.description, new.occurred_at,
          new.account_id, new.invoice_cufe, new.tags, new.original_currency, new.original_amount)
         is distinct from
         (old.amount, old.movement_type, old.category, old.description, old.occurred_at,
          old.account_id, old.invoice_cufe, old.tags, old.original_currency, old.original_amount)
  then
    raise exception 'Este movimiento viene de una factura y no se puede editar. Puedes eliminarlo.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists transactions_lock_invoice on public.transactions;
create trigger transactions_lock_invoice
  before update on public.transactions
  for each row execute function public.transactions_lock_invoice();

-- Facturas ya registradas.
do $$
declare r record;
begin
  for r in select transaction_id, user_id, cufe from public.dgi_receipts where transaction_id is not null loop
    perform public.mark_invoice_transactions(r.transaction_id, r.user_id, r.cufe);
  end loop;
end $$;
