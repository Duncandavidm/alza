-- 0082: cuentas de ahorro con dinero bloqueado hasta una fecha (ej. un
-- plazo fijo o "ahorro navideño" disponible en diciembre). Ese dia la app
-- pregunta "¿Ya está disponible tu dinero?" y ofrece pasarlo a otra cuenta.
-- null = sin bloqueo: el dinero siempre esta disponible y no se avisa.

alter table public.accounts
  add column if not exists available_on date;

-- (Incluye el arreglo de 0081 por si no se corrio: es idempotente.)
alter function public.debt_is_card(text, numeric) set search_path = public, pg_temp;
