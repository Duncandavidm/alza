-- RPC para sumar/restar el balance de una cuenta de forma atomica (evita
-- carreras read-modify-write cuando dos pantallas escriben a la vez, ej.
-- el ingreso ultra-rapido y el formulario detallado de movimiento).
create or replace function public.increment_account_balance(p_account_id uuid, p_delta numeric)
returns void
language sql
security invoker
as $$
  update public.accounts
  set balance = balance + p_delta
  where id = p_account_id;
$$;
