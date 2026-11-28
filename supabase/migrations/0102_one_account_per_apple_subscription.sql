-- 1.1.0: una suscripción de Apple = una cuenta MonAvi a la vez.
--
-- Cada Apple ID exige un teléfono verificado por Apple, y cada suscripción
-- Pro queda amarrada a un Apple ID. Hasta ahora verify-apple-receipt
-- aceptaba la misma suscripción (originalTransactionId) en varias cuentas:
-- bastaba "Restaurar compras" en otra cuenta para tener Pro y cashback en
-- las dos. Desde aquí, si otra cuenta reclama la suscripción, Pro pasa a la
-- cuenta nueva, la anterior lo pierde y se abre una revisión de cashback
-- en la cuenta nueva (caso legítimo: alguien que se creó una segunda
-- cuenta por error; el equipo la aprueba).

alter table public.cashback_reviews drop constraint if exists cashback_reviews_reason_check;
alter table public.cashback_reviews add constraint cashback_reviews_reason_check check (reason in (
  'ingreso_inusual', 'ingreso_a_la_medida', 'ingreso_editado', 'muchas_facturas',
  'dispositivo_compartido', 'telefono_repetido', 'apple_id_compartido', 'manual'));

create or replace function public.subscriptions_one_account_per_apple()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_moved int;
begin
  if new.apple_original_transaction_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.apple_original_transaction_id is not distinct from new.apple_original_transaction_id then
    return new;
  end if;

  update public.subscriptions
     set status = 'expired',
         expires_at = least(coalesce(expires_at, now()), now()),
         apple_original_transaction_id = null,
         apple_transaction_id = null
   where apple_original_transaction_id = new.apple_original_transaction_id
     and user_id <> new.user_id;
  get diagnostics v_moved = row_count;

  if v_moved > 0 then
    perform public.open_cashback_review(new.user_id, 'apple_id_compartido',
      jsonb_build_object('previous_accounts', v_moved));
  end if;
  return new;
end;
$$;

revoke execute on function public.subscriptions_one_account_per_apple() from public, anon, authenticated;

drop trigger if exists subscriptions_one_account_per_apple on public.subscriptions;
create trigger subscriptions_one_account_per_apple
  before insert or update of apple_original_transaction_id on public.subscriptions
  for each row execute function public.subscriptions_one_account_per_apple();

create unique index if not exists subscriptions_apple_original_unique
  on public.subscriptions (apple_original_transaction_id)
  where apple_original_transaction_id is not null;
