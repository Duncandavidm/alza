-- 0079: la tarjeta de credito funciona como una tarjeta real.
-- Cada deuda que es tarjeta (tiene cupo o se llama "tarjeta", "visa"...)
-- tiene una cuenta tipo credit_card vinculada (accounts.debt_id). Su saldo
-- va en negativo (lo que se debe), igual que cualquier cuenta: gastar con
-- la tarjeta lo baja y abonarle lo sube. Los dos lados se mantienen
-- iguales con triggers:
--   - gasto/abono en la cuenta -> debts.balance = -saldo de la cuenta
--   - pago registrado en la deuda (Pagar deuda) -> saldo de la cuenta

alter table public.accounts
  add column if not exists debt_id uuid unique references public.debts(id) on delete set null;

-- Dia del mes en que vence el pago (tarjetas y prestamos): para recordar
-- "Hoy toca pagar tu Visa" y registrar de que cuenta salio el pago.
alter table public.debts
  add column if not exists payment_day smallint check (payment_day between 1 and 31);

create or replace function public.debt_is_card(p_creditor text, p_credit_limit numeric)
 returns boolean
 language sql
 immutable
as $$
  select coalesce(p_credit_limit, 0) > 0
      or coalesce(p_creditor, '') ~* '(tarjeta|visa|master|amex|american express|clave|cr[eé]dito)';
$$;

-- Deuda -> cuenta: crea la cuenta de la tarjeta si falta y copia el saldo
-- cuando la deuda cambia por su lado (p. ej. "Pagar deuda").
create or replace function public.sync_card_account_from_debt()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  if exists (select 1 from public.accounts where debt_id = new.id) then
    if tg_op = 'UPDATE' and new.balance is distinct from old.balance then
      update public.accounts set balance = -new.balance, updated_at = now() where debt_id = new.id;
    end if;
    if tg_op = 'UPDATE' and new.creditor is distinct from old.creditor then
      update public.accounts set name = left(trim(new.creditor), 60), updated_at = now() where debt_id = new.id;
    end if;
  elsif new.status <> 'paid_off' and public.debt_is_card(new.creditor, new.credit_limit) then
    insert into public.accounts (user_id, name, type, balance, currency, debt_id)
    values (new.user_id, left(coalesce(nullif(trim(new.creditor), ''), 'Tarjeta de crédito'), 60), 'credit_card', -new.balance, 'USD', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists debts_sync_card_account on public.debts;
create trigger debts_sync_card_account
  after insert or update on public.debts
  for each row execute function public.sync_card_account_from_debt();

-- Cuenta -> deuda: un gasto con la tarjeta (o un abono a ella) mueve la
-- deuda. Si se vuelve a usar una tarjeta pagada, la deuda vuelve a activa.
create or replace function public.sync_debt_from_card_account()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $$
begin
  if pg_trigger_depth() > 1 or new.debt_id is null or new.balance is not distinct from old.balance then
    return new;
  end if;
  update public.debts
  set balance = greatest(-new.balance, 0),
      status = case when -new.balance > 0 and status = 'paid_off' then 'active' else status end,
      updated_at = now()
  where id = new.debt_id;
  return new;
end;
$$;

drop trigger if exists accounts_sync_card_debt on public.accounts;
create trigger accounts_sync_card_debt
  after update of balance on public.accounts
  for each row execute function public.sync_debt_from_card_account();

revoke all on function public.sync_card_account_from_debt() from public, anon, authenticated;
revoke all on function public.sync_debt_from_card_account() from public, anon, authenticated;

-- Tarjetas que ya existian: su cuenta. Se deja fuera la cuenta demo de
-- revision de Apple (ya tiene su propia cuenta de tarjeta).
insert into public.accounts (user_id, name, type, balance, currency, debt_id)
select d.user_id, left(coalesce(nullif(trim(d.creditor), ''), 'Tarjeta de crédito'), 60), 'credit_card', -d.balance, 'USD', d.id
from public.debts d
join auth.users u on u.id = d.user_id
where d.status <> 'paid_off'
  and public.debt_is_card(d.creditor, d.credit_limit)
  and u.email not ilike 'apple-review@%'
  and not exists (select 1 from public.accounts a where a.debt_id = d.id);
